import SwiftUI
import UIKit
import AVFoundation

// MARK: - 聊天 UI 组件（从 ChatView.swift 拆出，减小主文件体积）

// MARK: - v2.0.65 气泡小尾巴（iMessage 式：AI 左下 / 用户右下）
// v2.0.66：单 Shape 一体化（圆角矩形 + 尾巴同路径，之前的 ZStack overlay 方案尾巴被挤进气泡内不显示）

struct BubbleShape: Shape {
    let tailLeft: Bool   // 尾巴朝左（AI 消息）
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = radius
        let tailW: CGFloat = 8   // 尾巴凸出宽度
        let tailH: CGFloat = 16  // 尾巴高度
        var p = Path()
        // 圆角矩形主体
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
        // 尾巴：底部角落朝外凸出（与主体同填充色，天然一体）
        if tailLeft {
            p.move(to: CGPoint(x: rect.minX + r, y: rect.maxY - tailH))
            p.addLine(to: CGPoint(x: rect.minX - tailW, y: rect.maxY - tailH / 2))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX - r, y: rect.maxY - tailH))
            p.addLine(to: CGPoint(x: rect.maxX + tailW, y: rect.maxY - tailH / 2))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}


struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0   // v2.0.51：static let 不可变即并发安全（协议 get-only）
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// BigBang 全屏炸开载荷（fullScreenCover(item:) 需要 Identifiable）
struct BigBangPayload: Identifiable {
    let id = UUID()
    let text: String
}

/// AI 消息内容分段（代码块 / markdown 段）

struct MessageContentBlock: Identifiable {
    let id = UUID()
    enum Kind {
        case markdown(String)
        case code(String)
    }
    let kind: Kind
}

/// AI 消息分段渲染：markdown（容错解析，保留部分排版） / 代码块（等宽深色）
struct MessageBlockView: View {
    let block: MessageContentBlock
    // v2.0.38：聊天字体大小（与 MessageBubble 同源）
    @AppStorage("qingliao_font_size") private var fontSize = 14.0

    var body: some View {
        switch block.kind {
        case .markdown(let text):
            // v2.0.34：改用自研轻量渲染器（标题/加粗/斜体/代码/列表/引用），
            // 不再依赖 AttributedString(markdown:) 系统解析（iOS 上输出纯文本不可控）
            Text(MarkdownRenderer.render(text, baseSize: CGFloat(fontSize)))
                .lineSpacing(3)
                .textSelection(.enabled)
        case .code(let text):
            // v2.0.36：代码块加复制按钮（右上角）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("代码")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: max(10, CGFloat(fontSize) - 2), design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.bottom, 4)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - 聊天页（微信风格：AI 灰气泡左侧 / 用户深蓝气泡右侧，头像在气泡外）

struct MessageBubble: View {
    let message: ChatMessage
    var isHighlighted: Bool = false   // v2.0.43 搜索定位高亮
    var onRegenerate: () -> Void = {}
    var onBigBang: () -> Void = {}
    var onQuote: () -> Void = {}      // v2.0.36 引用回复
    var onDelete: () -> Void = {}     // v2.0.36 单条删除
    var onShare: () -> Void = {}      // v2.0.36 分享文本
    var onImageTap: () -> Void = {}   // v2.0.36 图片点击查看大图
    var onRetry: () -> Void = {}      // v2.0.59 发送失败重试
    // v2.0.38：聊天字体大小（设置页可调，实时生效）
    @AppStorage("qingliao_font_size") private var fontSize = 14.0
    // v2.0.65：深浅色气泡双色值 / 超长消息折叠
    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false
    // v2.0.81：AI 回复朗读状态（全局单例）
    @ObservedObject private var speech = SpeechManager.shared

    /// 用户气泡蓝：深色用深蓝，浅色用亮蓝（对比度适配）
    private var userBubbleColor: Color {
        isHighlighted
            ? (scheme == .dark ? Color(red: 0.20, green: 0.32, blue: 0.62) : Color(red: 0.38, green: 0.55, blue: 0.92))
            : (scheme == .dark ? Color(red: 0.13, green: 0.22, blue: 0.45) : Color(red: 0.27, green: 0.47, blue: 0.88))
    }
    /// AI 气泡灰：浅色模式更浅
    private var aiBubbleColor: Color {
        isHighlighted ? Color.accentColor.opacity(0.14)
            : (scheme == .dark ? Color(uiColor: .systemGray5) : Color(uiColor: .systemGray6))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                // v2.0.41：左侧留白 48→24，用户气泡更宽（右缘贴边）
                Spacer(minLength: 24)
            } else {
                // AI 头像（气泡外左侧）
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
            }

            // v2.0.66：气泡主体（单 Shape 背景带尾巴，不再用 ZStack overlay）
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                    // v2.0.61：语音条消息
                    if let path = message.audioPath {
                        AudioBubbleRow(path: path, durationText: message.content)
                            .padding(.vertical, 4)
                    }
                    if let img = message.imageDataURL, let uiImg = dataURLImage(img) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            // v2.0.36：点击查看大图
                            .onTapGesture { onImageTap() }
                    }
                    if !message.content.isEmpty {
                        if message.isUser {
                            Text(AttributedString(message.content))
                                .font(.system(size: CGFloat(fontSize)))   // v2.0.38 字号可调
                                .lineSpacing(3)
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                        } else {
                            // v2.0.65：AI 超长消息折叠（>800 字收成展开全文）
                            if message.content.count > 800 && !expanded {
                                Text(String(message.content.prefix(800)) + "…")
                                    .font(.system(size: CGFloat(fontSize)))
                                    .lineSpacing(3)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) { expanded = true }
                                } label: {
                                    Text("展开全文（剩余 \(message.content.count - 800) 字）")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            } else {
                                // AI 消息：代码块分段渲染（等宽 + 深色背景），其余 markdown
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(0..<contentBlocks.count, id: \.self) { i in
                                        MessageBlockView(block: contentBlocks[i])
                                    }
                                }
                            }
                        }
                    }
                    // v2.0.59：发送失败 → 重试按钮（红色，点击按原内容重发）
                    if message.isUser && message.failed {
                        Button {
                            onRetry()
                        } label: {
                            Label("发送失败，点击重试", systemImage: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    // v2.0.65：已送达小字（用户消息、非失败、非语音）
                    if message.isUser && !message.failed && message.audioPath == nil {
                        Text("已送达")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                    }
                    // v2.0.81：AI 消息朗读（点击播放/停止，中文 TTS）
                    if !message.isUser && !message.content.isEmpty {
                        Button {
                            SpeechManager.shared.toggle(message.content, id: message.id)
                        } label: {
                            Image(systemName: speech.speakingID == message.id
                                  ? "speaker.wave.2.fill" : "speaker.wave.2")
                                .font(.system(size: 11))
                                .foregroundStyle(speech.speakingID == message.id
                                                 ? Color.accentColor : .secondary)
                                .padding(.top, 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                // v2.0.68：用户反馈拿掉气泡尾巴（试了两版效果都不理想），回归纯圆角
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(message.isUser ? userBubbleColor : aiBubbleColor)
                )
                // v2.0.43 搜索定位高亮边框
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(isHighlighted ? Color.accentColor : .clear, lineWidth: 2)
                )
            .frame(maxWidth: 366, alignment: message.isUser ? .trailing : .leading)   // v2.0.41 气泡加宽 350→366（贴红线/近满宽）
            // v2.0.85c：气泡出现微动画（缩放 + 淡入，单条插入安全）
            .transition(.scale(scale: 0.94, anchor: message.isUser ? .trailing : .leading)
                .combined(with: .opacity))

            if message.isUser {
                // v2.0.65：用户头像（渐变圆 + 首字母，与 AI 头像对称）
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Q")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
            } else {
                // v2.0.41：AI 气泡右侧留白 48→10，气泡右缘贴红线（约距屏幕右 22pt）
                Spacer(minLength: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        // 长按：复制 / 引用 / 删除 / 分享 / 大爆炸 / 重新生成（AI 消息）
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Button {
                onQuote()
            } label: {
                Label("引用", systemImage: "quote.opening")
            }
            Button {
                onShare()
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            Button {
                onBigBang()
            } label: {
                Label("大爆炸", systemImage: "burst.fill")
            }
            if !message.isUser {
                Button {
                    onRegenerate()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 消息内容分段：``` 代码块 → 等宽深色块；其余 → markdown
    private var contentBlocks: [MessageContentBlock] {
        let parts = message.content.components(separatedBy: "```")
        var blocks: [MessageContentBlock] = []
        for (i, p) in parts.enumerated() {
            if i % 2 == 1 {
                // 代码块：去掉语言标记行
                let lines = p.split(separator: "\n", maxSplits: 1).map(String.init)
                let body = lines.count > 1 ? lines[1] : p
                blocks.append(.init(kind: .code(body.trimmingCharacters(in: .whitespacesAndNewlines))))
            } else if !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.init(kind: .markdown(p)))
            }
        }
        return blocks.isEmpty ? [.init(kind: .markdown(message.content))] : blocks
    }

    private func dataURLImage(_ urlStr: String) -> UIImage? {
        guard let comma = urlStr.firstIndex(of: ","),
              let data = Data(base64Encoded: String(urlStr[urlStr.index(after: comma)...])),
              let img = UIImage(data: data) else { return nil }
        return img
    }
}

// MARK: - 液态玻璃输入栏

struct ChatInputBar: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var streaming: Bool
    var onSend: () -> Void
    var onStop: () -> Void = {}
    var onPickAttachment: () -> Void = {}
    var onCamera: () -> Void = {}   // v2.0.38 拍照输入
    // 语音输入（按住说话）
    var isRecording: Bool = false
    var onVoiceStart: () -> Void = {}
    var onVoiceEnd: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPickAttachment) {
                Image(systemName: "paperclip")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)

            // v2.0.38：拍照输入
            Button(action: onCamera) {
                Image(systemName: "camera")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)

            if isRecording {
                // 录音中：红点 + 提示
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("松开结束")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.red)
                }
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.08), in: Capsule())
            } else {
                // v2.0.34：placeholder 用 overlay 自定义（vertical axis 的 TextField 自带
                // placeholder 在 lineLimit(2...6) 多行高下顶部对齐，视觉不居中）
                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...6)   // v2.0.35：1行起（原来2...6最小2行高→单行光标/文字偏上不居中）
                    .padding(.vertical, 9)
                    .padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)   // 文字超宽自动增高输入框，旧文字始终可见
                    .focused($focused)
                    .overlay {
                        if text.isEmpty {
                            Text("输入消息...")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Button {
                if streaming {
                    onStop()
                } else {
                    onSend()
                }
            } label: {
                Image(systemName: streaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
        .padding(.horizontal, 12)
    }
}

// MARK: - v2.0.61 语音条（本地播放）

struct AudioBubbleRow: View {
    let path: String
    let durationText: String   // 形如 "[语音 5″]"
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    private var dur: String {
        let digits = durationText.filter(\.isNumber)
        return digits.isEmpty ? "1″" : "\(digits)″"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                toggle()
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.pink, in: Circle())
            }
            .buttonStyle(.plain)

            Text(dur)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .leading)

            // 波形装饰（播放时高亮）
            HStack(spacing: 2.5) {
                ForEach(0..<14, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.pink.opacity(isPlaying ? 0.95 : 0.35))
                        .frame(width: 3, height: CGFloat(6 + (i % 5) * 4))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isPlaying)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDisappear { player?.stop() }
    }

    private func toggle() {
        if isPlaying {
            player?.stop()
            isPlaying = false
        } else {
            if player == nil {
                player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            }
            // 播放需 playback 类别（录音是 record）
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.currentTime = 0
            player?.play()
            isPlaying = true
        }
    }
}

// MARK: - v2.0.43 快捷指令面板（常用 prompt 模板，点击填充输入框）

struct QuickPromptSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let prompts: [(icon: String, name: String, prompt: String)] = [
        ("character.bubble", "翻译", "请将以下内容翻译成英文（保留原意）：\n"),
        ("list.bullet.rectangle", "总结", "请用 3-5 条要点总结以下内容：\n"),
        ("pencil.and.outline", "润色", "请润色以下文字，使其更通顺、专业、简洁：\n"),
        ("doc.text", "写周报", "请根据以下工作内容生成一份结构化周报：\n"),
        ("chevron.left.forwardslash.chevron.right", "写代码", "请实现以下功能，给出完整代码并简要解释：\n"),
        ("curlybraces", "解释代码", "请逐段解释以下代码的作用和逻辑：\n"),
        ("lightbulb", "头脑风暴", "请围绕以下主题给出 5 个有创意的点子：\n"),
        ("checklist", "待办清单", "请把以下内容整理成清晰的待办清单：\n"),
        ("textformat", "取标题", "请为以下内容取 3 个简洁贴切的标题：\n"),
        ("person.2", "角色扮演", "请扮演一个资深嵌入式硬件工程师，回答以下问题：\n"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("快捷指令")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(prompts, id: \.name) { p in
                        Button {
                            onPick(p.prompt)
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: p.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.accentColor)
                                Text(p.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - v2.0.36 图片大图查看器（双击/捏合缩放 + 保存相册）

struct ImageViewPayload: Identifiable {
    let id = UUID()
    let images: [UIImage]   // v2.0.62：全部图片消息（相册翻页）
    var index: Int
}

// v2.0.62：相册式查看器——横向滑动翻页 + 每页双击/捏合缩放 + 保存
struct ImageViewer: View {
    let images: [UIImage]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(0..<images.count, id: \.self) { i in
                    ImageViewerPage(image: images[i])
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            VStack {
                HStack {
                    if images.count > 1 {
                        Text("\(index + 1) / \(images.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.leading, 16)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
                Spacer()
                Button {
                    UIImageWriteToSavedPhotosAlbum(images[index], nil, nil, nil)
                } label: {
                    Label("保存到相册", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 44)
            }
        }
    }
}

// 单图页：双击/捏合缩放
struct ImageViewerPage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .animation(.spring(duration: 0.25), value: scale)
            .gesture(MagnificationGesture()
                .onChanged { scale = max(1, min($0, 4)) })
            .onTapGesture(count: 2) {
                scale = scale == 1 ? 2.2 : 1
            }
    }
}

// MARK: - v2.0.36 会话导出文档（.txt）

struct ChatLogDocument: FileDocument {
    var text: String
    static var readableContentTypes: [UTType] { [.plainText] }
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
