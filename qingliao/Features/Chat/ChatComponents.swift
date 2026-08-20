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
        case table([[String]])   // v2.0.87d：markdown 表格（表头+数据行）
        case image(String)       // v2.0.128：AI 回复中的图片（URL 或 data URL）
    }
    let kind: Kind
}

/// AI 消息分段渲染：markdown（容错解析，保留部分排版） / 代码块（等宽深色）
/// v2.0.125：markdown 段改用 SelectableTextLabel（UITextView）——长按菜单含「选择文本」，
///           点选后文字从手按位置选中、出现原生拖动手柄可自由拖动；代码块/表格保留 SwiftUI 菜单。
struct MessageBlockView: View {
    let block: MessageContentBlock
    // v2.0.38：聊天字体大小（与 MessageBubble 同源）
    @AppStorage("qingliao_font_size") private var fontSize = 15.0   // v2.0.87r：默认15号
    // v2.0.128：AI 输出行高（设置页滑条控制，0-6；默认 1.0 紧凑）
    @AppStorage("qingliao_ai_line_spacing") private var aiLineSpacing = 1.0
    // v2.0.125：长按菜单回调（markdown 段 → UITextView 原生编辑菜单；代码块/表格 → SwiftUI 菜单）
    var onCopy: () -> Void = {}
    var onQuote: () -> Void = {}
    var onShare: () -> Void = {}
    var onBigBang: () -> Void = {}
    var onDelete: () -> Void = {}
    var onRegenerate: (() -> Void)? = nil
    var onWithdraw: (() -> Void)? = nil
    // v2.0.128：AI 图片点击打开大图（传图片 URL/data URL）
    var onImageTap: (String) -> Void = { _ in }
    // v3.0.17：流式输出中用 SwiftUI Text 渲染（UITextView 在流式高频更新下有锁旧窄布局/字体缩放 bug 家族，
    // 见 references/ui-textview-layout-shrink.md；流式中无需长按菜单，落库后恢复 SelectableTextLabel）
    var useSwiftUIText = false

    // v3.0.2 性能：缓存 markdown 渲染结果——流式每段更新 parent.messages 会触发子视图重算，
    // 若每次 body 都 MarkdownRenderer.render() 重新解析，长文本/流式下是滚动+更新卡顿主因。
    // 用 @State 缓存 + 内容指纹：文本/字号未变 → 复用已渲染的 NSAttributedString。
    @State private var cachedKey = ""
    @State private var cachedAttr: NSAttributedString? = nil

    /// 渲染并缓存 markdown（内容指纹：文本+字号）
    private func cachedRender(_ text: String) -> NSAttributedString {
        let key = "\(text.hashValue)|\(fontSize)"
        if key != cachedKey || cachedAttr == nil {
            cachedKey = key
            cachedAttr = NSAttributedString(MarkdownRenderer.render(text, baseSize: CGFloat(fontSize)))
        }
        return cachedAttr ?? NSAttributedString(string: text)
    }

    /// v3.0.17：流式 SwiftUI Text 用 —— 复用同一缓存转 AttributedString
    private func cachedRenderText(_ text: String) -> AttributedString {
        AttributedString(cachedRender(text))
    }

    /// 代码块/表格共用的 SwiftUI 长按菜单（与原气泡级菜单项一致）
    @ViewBuilder
    private var bubbleMenu: some View {
        Button {
            onCopy()
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
        if let onRegenerate {
            Button {
                onRegenerate()
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
            }
        }
        if let onWithdraw {
            Button {
                onWithdraw()
            } label: {
                Label("撤回", systemImage: "arrow.uturn.backward")
            }
        }
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    var body: some View {
        switch block.kind {
        case .markdown(let text):
            if useSwiftUIText {
                // v3.0.17：流式输出中的 AI 长文 —— SwiftUI Text 原生渲染，无 UITextView 布局锁/字体缩放问题
                Text(cachedRenderText(text))
                    .font(.system(size: CGFloat(fontSize)))
                    .lineSpacing(aiLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // v2.0.125：UITextView 渲染 —— 长按文字弹菜单，点「选择文本」从手按位置选中可拖动
                // v3.0.2 性能：用 cachedRender 缓存 markdown 渲染结果（避免流式/滚动反复重解析）
                SelectableTextLabel(
                    attributedText: cachedRender(text),
                    fallbackColor: .label,
                    lineSpacingFromSettings: true,   // v2.0.130：AI 消息行距实时读设置
                    fillWidth: true,   // v3.0.11 fix：AI 消息满容器宽（流式不跳变）
                    onCopy: onCopy,
                    onQuote: onQuote,
                    onShare: onShare,
                    onBigBang: onBigBang,
                    onDelete: onDelete,
                    onRegenerate: onRegenerate,
                    onWithdraw: onWithdraw
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image(let url):
            // v2.0.128：AI 直接发图 —— URL 用 AsyncImage，data URL 本地解码；点击打开大图
            AIImageView(url: url)
                .onTapGesture { onImageTap(url) }
                .contextMenu { bubbleMenu }
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
                        .font(.system(size: max(12, CGFloat(fontSize)), design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.bottom, 4)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contextMenu { bubbleMenu }
        case .table(let rows):
            // v2.0.87d：markdown 表格渲染（表头加粗 + 斑马纹 + 横向滚动）
            MarkdownTableView(rows: rows)
                .contextMenu { bubbleMenu }
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
    var onWithdraw: () -> Void = {}   // v2.0.92 消息撤回（10 秒内）
    // v2.0.128：AI 消息内图片点击（传 URL/data URL，打开大图）
    var onAIImageTap: (String) -> Void = { _ in }
    // v3.0.15：AI 流式输出中——头像显示粒子球（orbits 流动），替代静态脑形标
    var streamingAvatar: Bool = false
    // v3.0.17：流式输出中 markdown 段用 SwiftUI Text 渲染（绕开 UITextView 流式锁窄布局 bug 家族）
    var streamingText: Bool = false
    // v2.0.38：聊天字体大小（设置页可调，实时生效）
    @AppStorage("qingliao_font_size") private var fontSize = 15.0   // v2.0.87r：默认15号
    // v2.0.128：AI 输出行高（设置页滑条，实时生效）
    @AppStorage("qingliao_ai_line_spacing") private var aiLineSpacing = 1.0
    // v2.0.65：深浅色气泡双色值 / 超长消息折叠
    @Environment(\.colorScheme) private var scheme
    // v2.0.130：AI 发图 MEDIA 路径 → 服务器图片 URL（读 App 配置的服务器地址）
    @AppStorage("qingliao_server") private var serverURL = ""
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

    /// v2.0.125：撤回条件（自己的消息 + 10 秒内 + 未撤回 + 未失败），菜单项按此显隐
    private var canWithdraw: Bool {
        if message.isUser, !message.withdrawn, !message.failed,
           let ts = message.timestamp {
            return Date().timeIntervalSince1970 - ts / 1000 < 10
        }
        return false
    }

    /// v2.0.125：图片/文件卡片的长按菜单（文字区由 UITextView 编辑菜单接管，不再走这里）
    @ViewBuilder
    private var cardMenu: some View {
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
        if canWithdraw {
            Button {
                onWithdraw()
            } label: {
                Label("撤回", systemImage: "arrow.uturn.backward")
            }
        }
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    /// v3.0.15：AI 头像——流式输出中 = 粒子球（渐变底 + orbits 粒子流动），否则脑形标
    /// 拆独立计算属性：防止 body 巨型表达式 type-check 超时（v3.0.15 CI 实测）
    /// v3.0.16：头像粒子用定制大参数（默认参数按 300pt 基准缩放，30pt 下仅 ~0.2pt 不可见）
    @ViewBuilder
    private var aiAvatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
            if streamingAvatar {
                // v3.0.17：彩色粒子（亮蓝/紫/粉/白，深浅色模式都醒目），大参数保证 30pt 可见
                OrbCanvasView(mode: .orbits, size: 30,
                              opts: OrbOpts(orbitN: 8, ghostN: 26, ghostR: 2.8, ghostA: 0.9,
                                            particles: 4, partR: 3.4, partRDepth: 2.6,
                                            rsPow: 0.6, rMin: 0.9),
                              dotColors: [
                                Color(red: 0.55, green: 0.72, blue: 1.0),
                                Color(red: 0.65, green: 0.55, blue: 1.0),
                                Color(red: 1.0, green: 0.60, blue: 0.85),
                                .white
                              ])
                    .allowsHitTesting(false)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                // v2.0.41：左侧留白 48→24，用户气泡更宽（右缘贴边）
                Spacer(minLength: 24)
            } else {
                aiAvatar
            }

            // v2.0.66：气泡主体（单 Shape 背景带尾巴，不再用 ZStack overlay）
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                    // v2.0.92：撤回消息 → 灰色"已撤回"占位（内容不再显示）
                    if message.withdrawn {
                        Text("已撤回")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    } else if let img = message.imageDataURL, let uiImg = dataURLImage(img) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            // v2.0.36：点击查看大图
                            .onTapGesture { onImageTap() }
                            // v2.0.125：图片长按菜单（原气泡级菜单移到这里，不抢占文字长按）
                            .contextMenu { cardMenu }
                    }
                    if !message.content.isEmpty {
                        if message.isUser {
                            // v2.0.87q：文件消息微信风格卡片（图标+文件名+状态）
                            if let file = parseFileMessage(message.content) {
                                FileMessageCard(file: file)
                                    // v2.0.125：文件卡片长按菜单（原气泡级菜单移到这里）
                                    .contextMenu { cardMenu }
                            } else {
                                // v2.0.125：UITextView 渲染 —— 长按弹菜单（复制/引用/分享/大爆炸/选择文本/撤回/删除）
                                SelectableTextLabel(
                                    attributedText: NSAttributedString(string: message.content, attributes: [
                                        .font: UIFont.systemFont(ofSize: CGFloat(fontSize)),
                                        .foregroundColor: UIColor.white
                                    ]),
                                    fallbackColor: .white,
                                    lineSpacing: 3,
                                    onCopy: { UIPasteboard.general.string = message.content },
                                    onQuote: onQuote,
                                    onShare: onShare,
                                    onBigBang: onBigBang,
                                    onDelete: onDelete,
                                    onRegenerate: nil,
                                    onWithdraw: canWithdraw ? onWithdraw : nil
                                )
                            }
                        } else {
                            // v3.0.15：AI 消息全文展示（取消 v2.0.65 超长消息折叠）——代码块分段渲染（等宽 + 深色背景），其余 markdown
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(0..<contentBlocks.count, id: \.self) { i in
                                    MessageBlockView(block: contentBlocks[i],
                                                    onCopy: { UIPasteboard.general.string = message.content },
                                                    onQuote: onQuote,
                                                    onShare: onShare,
                                                    onBigBang: onBigBang,
                                                    onDelete: onDelete,
                                                    onRegenerate: onRegenerate,
                                                    onWithdraw: nil,
                                                    onImageTap: { url in onAIImageTap(url) },   // v2.0.128：AI 图片点击打开大图
                                                    useSwiftUIText: streamingText)   // v3.0.17：流式中 SwiftUI Text 渲染
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
                    // v2.0.65：已送达小字（用户消息、非失败、非语音、未撤回）
                    // v2.0.87q：加 ✓ 图标（微信式送达状态）
                    // v2.0.88：排队中的消息显示 ⏳ 排队中（AI 回答完自动发送）
                    if message.isUser && !message.failed && !message.withdrawn {
                        HStack(spacing: 2.5) {
                            Image(systemName: message.queued ? "hourglass" : "checkmark")
                                .font(.system(size: 7.5, weight: .bold))
                            Text(message.queued ? "排队中" : "已送达")
                                .font(.system(size: 9.5))
                        }
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
                    // v2.0.96b：Agent 回复标记（工具调用回复小标签）
                    if message.agent {
                        Text("Agent 回复")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(LinearGradient(colors: [.blue, .indigo, .pink],
                                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                // v2.0.68：用户反馈拿掉气泡尾巴（试了两版效果都不理想），回归纯圆角
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(message.withdrawn ? aiBubbleColor : (message.isUser ? userBubbleColor : aiBubbleColor))   // v2.0.92：撤回统一灰
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
        // v2.0.125：长按菜单按区域分发 —— 文字区由 SelectableTextLabel 的 UITextView 编辑菜单接管
        //（复制/引用/分享/大爆炸/选择文本/重新生成/撤回/删除）；图片/文件卡片挂 cardMenu；
        // 代码块/表格走 MessageBlockView 内部 SwiftUI 菜单。
        // ⚠️ 气泡级 contextMenu 会抢占 UITextView 长按手势（v2.0.122 实测 bug），必须移除。
    }

    /// 消息内容分段：``` 代码块 → 等宽深色块；其余 → markdown
    private var contentBlocks: [MessageContentBlock] {
        let parts = Self.expandMediaMarks(message.content, serverURL: serverURL).components(separatedBy: "```")
        var blocks: [MessageContentBlock] = []
        for (i, p) in parts.enumerated() {
            if i % 2 == 1 {
                // 代码块：去掉语言标记行
                let lines = p.split(separator: "\n", maxSplits: 1).map(String.init)
                let body = lines.count > 1 ? lines[1] : p
                blocks.append(.init(kind: .code(body.trimmingCharacters(in: .whitespacesAndNewlines))))
            } else if !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // v2.0.87d：markdown 段内拆出表格块（| a | b | + 分隔行）
                for k in Self.splitMarkdownTable(p) {
                    blocks.append(.init(kind: k))
                }
            }
        }
        return blocks.isEmpty ? [.init(kind: .markdown(message.content))] : blocks
    }

    /// v2.0.130：AI 发图 —— Hermes 回复的 MEDIA:/路径 协议 → markdown 图片语法
    /// 转成 `![图片](<服务器>/api/stream/media?p=<base64url 容器路径>)`，
    /// 由 splitMarkdownImages 拆成图片块；服务器端该端点免鉴权只读图片。
    private static func expandMediaMarks(_ text: String, serverURL: String) -> String {
        guard text.contains("MEDIA:") else { return text }
        guard let re = try? NSRegularExpression(pattern: #"MEDIA:\s*([^\s\n]+)"#) else { return text }
        let ns = text as NSString
        var result = text
        var offset = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let rawPath = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !rawPath.isEmpty else { continue }
            // 容器路径 → base64url（服务器端映射 /opt/data → 宿主 hermes-data）
            let b64 = Data(rawPath.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let imgMarkdown = "![图片](\(serverURL)/api/stream/media?p=\(b64))"
            let fullRange = NSRange(location: m.range.location + offset, length: m.range.length)
            result = (result as NSString).replacingCharacters(in: fullRange, with: imgMarkdown)
            offset += imgMarkdown.count - m.range.length
        }
        return result
    }

    /// v2.0.87d：markdown 表格检测拆分（连续 | 行 → 表格块，其余保持 markdown）
    /// v2.0.128：非表格行内再拆出图片块（![alt](url)）——AI 直接发图
    private static func splitMarkdownTable(_ text: String) -> [MessageContentBlock.Kind] {
        let lines = text.components(separatedBy: "\n")
        var result: [MessageContentBlock.Kind] = []
        var table: [String] = []
        func flush() {
            if !table.isEmpty {
                if let rows = parseTable(table) {
                    result.append(.table(rows))
                } else {
                    result.append(contentsOf: splitMarkdownImages(table.joined(separator: "\n")))
                }
                table = []
            }
        }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") && t.hasSuffix("|") {
                table.append(line)
            } else {
                flush()
                result.append(contentsOf: splitMarkdownImages(line))
            }
        }
        flush()
        return result
    }

    /// v2.0.128：行内拆出 markdown 图片语法 ![alt](url) → 图片块（URL 或 data URL），其余保持 markdown
    private static func splitMarkdownImages(_ line: String) -> [MessageContentBlock.Kind] {
        guard let re = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)\s]+)\)"#) else {
            return [.markdown(line)]
        }
        let ns = line as NSString
        let matches = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [.markdown(line)] }
        var result: [MessageContentBlock.Kind] = []
        var pos = 0
        for m in matches {
            if m.range.location > pos {
                let pre = ns.substring(with: NSRange(location: pos, length: m.range.location - pos))
                if !pre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.markdown(pre))
                }
            }
            let url = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            result.append(.image(url))
            pos = m.range.location + m.range.length
        }
        if pos < ns.length {
            let tail = ns.substring(from: pos)
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.markdown(tail))
            }
        }
        return result.isEmpty ? [.markdown(line)] : result
    }

    /// v2.0.87d：表格行解析（首行表头，第二行 |---| 分隔则跳过）
    private static func parseTable(_ lines: [String]) -> [[String]]? {
        let rows = lines.map { line -> [String] in
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("|") { s.removeFirst() }
            if s.hasSuffix("|") { s.removeLast() }
            return s.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard rows.count >= 2 else { return nil }
        let sep = rows[1]
        let isSep = sep.allSatisfy { $0.isEmpty || $0.allSatisfy { $0 == "-" || $0 == ":" } }
        let data = isSep ? Array(rows.dropFirst(2)) : Array(rows.dropFirst(1))
        let header = rows[0]
        return data.isEmpty ? [header] : [header] + data
    }

}

// MARK: - v2.0.128 AI 直接发图（消息内图片渲染）

/// AI 回复中的图片：data URL 本地解码；http(s) URL 异步加载。
/// ⚠️ 加载链路必须兼容自签证书服务器（用户 NAS 就是）：URLSession 对外部公开图正常，
///    失败时降级 StreamHTTPClient（忽略证书链校验）——不能用纯 AsyncImage（自签证书必失败）。
/// 尺寸：圆角 12、最大宽 240、最大高 240（与原用户图片消息一致），点击由外层 onTapGesture 处理。
struct AIImageView: View {
    let url: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        if url.hasPrefix("data:image/") {
            // base64 data URL → 本地解码（复用 ImageCache）
            if let img = dataURLImage(url) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                placeholder
            }
        } else if let img = image {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 240, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if failed {
            placeholder
        } else {
            ProgressView()
                .frame(width: 240, height: 120)
                .task { await loadRemote() }
        }
    }

    /// 远程加载：URLSession 优先 → 失败降级 StreamHTTPClient（自签证书）
    @MainActor
    private func loadRemote() async {
        guard let u = URL(string: url), url.hasPrefix("http") else {
            failed = true
            return
        }
        // 0) 缓存命中直接显示
        if let cached = cachedRemoteImage(url) {
            image = cached
            return
        }
        // 1) URLSession（外部公开图，Ats 允许 https）
        if let (data, _) = try? await URLSession.shared.data(from: u),
           let img = UIImage(data: data) {
            setRemoteImageCache(url, img, cost: data.count)
            image = img
            return
        }
        // 2) 降级 CFStream 直连（自签证书服务器：忽略证书链校验）
        if let host = u.host, let scheme = u.scheme {
            let port = UInt16(u.port ?? (scheme == "https" ? 443 : 80))
            let path = u.path + (u.query.map { "?" + $0 } ?? "")
            let client = StreamHTTPClient()
            let result = await Task.detached(priority: .userInitiated) {
                try? client.request(host: host, port: port, isTLS: scheme == "https",
                                    method: "GET", path: path, headers: [:], body: nil, timeout: 15)
            }.value
            if let (data, code) = result, (200..<300).contains(code),
               let img = UIImage(data: data) {
                setRemoteImageCache(url, img, cost: data.count)
                image = img
                return
            }
        }
        failed = true
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "photo")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("图片加载失败")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 200, height: 100)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    // v2.0.96：语音转文字模式（长按发送按钮进入；Siri 彩色图标 + 输入框流光）
    var voiceMode: Bool = false
    var onVoiceModeToggle: () -> Void = {}
    // v2.0.100：转写中动画（输入框「语音转换中…」+ 按钮转圈）
    var transcribing: Bool = false
    // v2.0.101：转写停止按钮回调
    var onCancelTranscribe: () -> Void = {}
    // v2.0.106：长按输入框触发语音转文字（效果与长按发送键一致，不弹键盘）
    // v2.0.109b：onChanged 记录按下瞬间键盘可见状态（down 时键盘未弹/已弹，比时间戳推断可靠）
    var onLongPressInput: (Bool) -> Void = { _ in }
    // v3.0.4：语音功能启用开关——云端模式无后端 ASR，关闭全部语音入口（长按/按钮）
    var voiceEnabled: Bool = true
    @Environment(KeyboardObserver.self) private var kbEnv
    @State private var pressKeyboardUp = false
    // v2.0.129：Siri 圆球输入（设置开关，默认开）——默认状态是圆球，单击展开输入框，长按语音转文字
    @AppStorage("qingliao_ball_input") private var ballInput = true
    @State private var ballExpanded = false   // 球 → 输入框展开态（切会话由外层 .id() 重建复位）
    // v2.0.132：点击球触发全屏粒子爆发（满屏散开）——由外层 ChatView 挂全屏特效层（局部 BurstEffect 已删，视觉重叠且双 TimelineView 掉帧）
    var onFullBurst: () -> Void = {}

    var body: some View {
        Group {
            if ballInput && !ballExpanded {
                // 🟣 v2.0.129 球态：Siri 多彩光晕圆球居中（单击展开输入框 / 长按语音转文字）
                // 语音转文字/转写过程中球保持特效，转写完成自动展开（onChange 处理）
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SiriBallView(isRecording: isRecording, voiceMode: voiceMode,
                                 transcribing: transcribing,
                                 thinking: streaming,
                                 onTap: {
                                                                                                      // 转写中点击不响应（避免打断）
                                                                                                      guard !transcribing else { return }
                                                                                                      // v2.0.130：炫酷展开 —— 全屏粒子爆发（满屏散开）+ 输入框从球心缩放展开
                                                                                                      // v2.0.132 优化：局部 BurstEffect 已删（与全屏特效重叠且双 TimelineView 掉帧），
                                                                                                      // 动画改短 0.35s、避免四路动画叠加掉帧
                                                                                                      // v2.0.133e：弹键盘再顺延到 0.4s——等 spring 展开完全结束才弹，
                                                                                                      // 与键盘动画完全串行（原 0.28s 时展开动画还在回弹，两段动画抢帧 → 衔接生硬）
                                                                                                      onFullBurst()
                                                                                                      withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                                                                                                          ballExpanded = true
                                                                                                      }
                                                                                                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                                                                          focused = true   // 键盘动画与展开动画串行，衔接平滑
                                                                                                      }
                                                                                                  },
                                 onLongPress: {
                                     // 长按 = 语音转文字（球保持特效，不展开输入框）
                                     // v3.0.4：云端模式无语音 → 长按球展开输入框（等同点击）
                                     guard voiceEnabled else {
                                         onFullBurst()
                                         withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                                             ballExpanded = true
                                         }
                                         return
                                     }
                                     guard !transcribing else { return }
                                     onLongPressInput(kbEnv.isVisible)
                                 })
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 12)   // v2.0.132：球态下沉；v2.0.137：下沉贴 Dock；v2.0.140：再下移贴近（球底距 Dock 顶约 12pt）
                // v2.0.130：球移除过渡——v2.0.132 优化：去掉 blurReplace（每帧离屏模糊最吃 GPU），只留缩放+淡出
                .transition(.scale(1.35).combined(with: .opacity))
            } else {
                fullInputBar
                    // v2.0.130：输入框从球心缩放展开——v2.0.132 优化：同样去掉 blurReplace
                    .transition(.scale(0.5).combined(with: .opacity))
            }
        }
        // v2.0.129：球态下语音转写完成（transcribing true→false 且已有转写文字）→ 自动展开输入框 + 弹键盘
        .onChange(of: transcribing) { _, newVal in
            if ballInput, !ballExpanded, !newVal, !text.isEmpty {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    ballExpanded = true
                }
                // v2.0.133e：与点击路径统一——等展开动画结束再弹键盘（0.35s+0.05 余量），串行不抢帧
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    focused = true   // 转写完成弹键盘（用户细节③确认）
                }
            }
        }
    }

    /// 完整输入栏（原 ChatInputBar 内容）
    private var fullInputBar: some View {
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
                    .padding(.vertical, 12)   // v2.0.93f：9→12 输入框加高（用户反馈太窄）
                    .padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)   // 文字超宽自动增高输入框，旧文字始终可见
                    .focused($focused)
                    // v2.0.106：长按输入框 = 进入语音转文字（与长按发送键同效；收键盘由 ChatView 处理）
                    // v2.0.106b：onLongPressGesture 被 UITextField 内置长按(放大镜/选择)拦截不触发
                    //           → 改 simultaneousGesture 与系统手势共存触发
                    // v2.0.109b：onChanged（down 瞬间）记录键盘可见状态——键盘开=true 保持，关=false 收回
                    // v3.0.4 fix：云端无语音 → 输入框长按不触发语音转文字（保留系统默认长按）
                    //           （用 .simultaneousGesture 里 if/else 各自挂同类型 LongPressGesture，规避泛型不一致）
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: voiceEnabled ? 0.4 : 3600)
                            .onChanged { _ in
                                pressKeyboardUp = kbEnv.isVisible
                            }
                            .onEnded { _ in
                                guard voiceEnabled else { return }
                                onLongPressInput(pressKeyboardUp)
                            }
                    )
                    .overlay {
                        if text.isEmpty {
                            if transcribing {
                                // v2.0.100：转写中动画（waveform 图标 + 文字脉冲）
                                HStack(spacing: 6) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 12))
                                        .symbolEffect(.pulse)
                                    Text("语音转换中…")
                                        .font(.system(size: 15))
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                            } else {
                                Text("输入消息...")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
            }

            // v2.0.88：AI 回答中也可继续发送（消息排队，答完自动逐条回）；
            // 停止按钮独立保留（取消当前回答 + 清空队列）
            if streaming {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // v2.0.96：发送按钮——普通发送；语音模式下点击=退出；长按=进入语音转文字（Siri 彩色图标）
            // v2.0.96b：Button 内置手势会拦截 onLongPressGesture → 改自定义视图 + 显式 Tap/LongPress
            // v2.0.98：onTapGesture+onLongPressGesture 叠加 = 两个独立手势系统在手势激活中改
            //          视图树（voiceMode 切换重建按钮）→ 实测 SIGTRAP 闪退（crash_reports 4 次）。
            //          改用 ExclusiveGesture（长按优先、互斥），onEnded 时手势已结束，视图重建安全。
            // v2.0.100：transcribing 时按钮显示转圈（转换中动画）
            // v2.0.101：转圈旁加红色停止按钮（随时中断转换）；手势只在非转写时挂载（停止按钮独立可点）
            Group {
                if transcribing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 32, height: 32)
                        Button(action: onCancelTranscribe) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.red.opacity(0.85), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Image(systemName: voiceMode ? "waveform" : "arrow.up")
                        .font(.system(size: voiceMode ? 15 : 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                        .gesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .exclusively(before: TapGesture())
                                .onEnded { value in
                                    // .first = 长按成功（语音模式开关）；.second = 轻点（发送/退出）
                                    switch value {
                                    case .first:
                                        // v3.0.4：云端无语音 → 长按等同轻点发送
                                        if voiceEnabled {
                                            onVoiceModeToggle()
                                        } else {
                                            onSend()
                                        }
                                    case .second:
                                        if voiceMode {
                                            onVoiceModeToggle()
                                        } else {
                                            onSend()
                                        }
                                    }
                                }
                        )
                }
            }
            .background(
                LinearGradient(colors: voiceMode ? [.blue, .indigo, .pink] : [.blue, .indigo],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // v2.0.87e：原生液态玻璃输入栏（iOS 26+）
        .background { Capsule().glassEffect() }
        // v2.0.87s：等待回复特效（v2.0.87ay：改回 87 版效果——内部旋转流光，Siri 淡雅）
        // v2.0.96：语音转文字模式同样开启 Siri 流光
        .overlay {
            if (streaming || voiceMode) && UserDefaults.standard.bool(forKey: "qingliao_input_glow") {
                // v2.0.139 性能：流光 60→30fps（旋转渐变肉眼无差，重绘开销减半）
                let schedule: AnimationTimelineSchedule = .animation(minimumInterval: 1.0 / 30.0)
                TimelineView(schedule) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let angle = (t * 70).truncatingRemainder(dividingBy: 360)
                    // 内部流光：Siri 淡雅蓝紫粉红旋转（87 版效果）
                    Capsule().fill(
                        AngularGradient(
                            colors: [.blue.opacity(0.22), .indigo.opacity(0.22),
                                     .pink.opacity(0.22), .red.opacity(0.16), .blue.opacity(0.22)],
                            center: .center, angle: .degrees(angle)
                        )
                    )
                    .shadow(color: .indigo.opacity(0.30), radius: 6)
                    .allowsHitTesting(false)   // v2.0.87al：不拦截点击（停止按钮可点）
                }
            } else {
                Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
        .padding(.horizontal, 18)   // v2.0.87aw：输入框宽度收窄（12→18）
    }
}

// MARK: - v2.0.132 全屏爆发特效（点击智能球：满屏粒子散开）

/// 点击智能球展开输入框时的全屏级爆发：粒子从球心（底部中央）向全屏飞散。
/// 触发方在 ~0.95s 后移除本层。
/// v2.0.135 性能修复：扩散波纹从 Canvas 逐帧 stroke（每帧 3 个全屏大椭圆）改为
/// Core Animation 隐式动画（GPU 合成）——但 60fps 下 3 层全屏大圆持续放大插值仍卡顿，
/// v2.0.138 决定直接移除波纹层（修不好宁可整体移除，用户确认），只保留粒子特效。
struct FullScreenBurst: View {
    @State private var spawn = Date()

    var body: some View {
        // 锁 60fps（v2.0.133d：ProMotion 120Hz 下每帧全屏 Canvas 重绘开销大，60fps 肉眼已顺滑）
        // v2.0.134 修复 CI：TimelineView content 只返回简单类型 BurstCanvas——原内联 Canvas 多语句闭包
        // 类型错误会让编译器报外层 generic parameter 'Content' could not be inferred（check_swift.sh 查不出）
        GeometryReader { geo in
            // 粒子层：160 颗飞散粒子（v2.0.138：波纹层已移除，仅粒子）
            let schedule: AnimationTimelineSchedule = .animation(minimumInterval: 1.0 / 60.0)
            TimelineView(schedule) { context in
                BurstCanvas(date: context.date, spawn: spawn)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 全屏爆发粒子 Canvas 绘制层（v2.0.134 从 FullScreenBurst 提出，独立编译定位类型错误）。
/// 确定性伪随机粒子：160 颗从球心（底部中央）向全屏飞散，先快后慢爆开感 + 平滑淡出。
/// 性能：单位圆 Path 循环外建一次，循环内 translate/scale 变换复用（原每帧 320 次 Path 分配是掉帧主因）。
struct BurstCanvas: View {
    let date: Date
    let spawn: Date

    /// 确定性伪随机（0-1），粒子参数稳定不闪烁
    private func hash(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i * 127 + salt * 311)) * 43758.5453
        return v - v.rounded(.down)
    }

    var body: some View {
        let t = date.timeIntervalSince(spawn)
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // v2.0.135：扩散波纹移出 Canvas（改隐式动画），v2.0.138：波纹层整体移除（仍卡顿），
            // 仅保留粒子绘制——160 颗小圆，绘制面积小
            // 发射原点：底部中央（智能球位置，Dock 上方；v2.0.137 随球下沉同步 h-164；v2.0.140 球再下移同步 h-136）
            let origin = CGPoint(x: w / 2, y: h - 136)
            // 粒子群：160 颗。v2.0.133 放烟花参数：
            //    速度调慢（250-650）且减速加大（0.25→0.55）= 先快后慢的爆开感；
            //    生命周期拉长（0.7-1.2s）平滑淡出（v2.0.133c：去掉末段 sin 闪烁，用户觉得闪烁多余）
            //    v2.0.133d：单位圆 Path 复用 + translate/scale 变换绘制（原每帧 320 次
            //    Path(ellipseIn:) 对象分配是掉帧主因，现仅 1 个 Path 实例复用）
            //    v2.0.137：粒子提速（480-950）提寿命（0.9-1.45s）+ 减重力下拉（70→25），
            //    最大飞行距离 ~826pt 可冲到灵动岛/屏幕顶，不再只在下半屏；向上粒子占比 92%
            let colors: [Color] = [.blue, .indigo, .pink, .purple]
            let unitDot = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
            // v2.0.139 性能：160→120 颗（-25% fill），且光晕大圆只对半数粒子绘制（-50% 光晕 fill），
            // 每帧绘制调用 320 → ~180（-44%）；视觉密度几乎无差（小粒子光晕本就淡）
            for i in 0..<120 {
                let life = 0.9 + hash(i, 1) * 0.55
                guard t < life else { continue }
                let progress = t / life
                let speed = 480 + hash(i, 2) * 470
                let upBias = hash(i, 3) < 0.92
                let angle: Double
                if upBias {
                    angle = .pi * (0.08 + hash(i, 4) * 0.84)   // 收窄朝上扇形（8%-92%），直冲顶部灵动岛
                } else {
                    angle = .pi * 2 * hash(i, 5)
                }
                let dist = speed * t * (1 - 0.55 * progress)   // 减速 0.25→0.55：爆开初速快、末端近乎悬停
                let x = origin.x + CGFloat(cos(angle)) * dist
                let y = origin.y - CGFloat(sin(angle)) * dist + 25 * CGFloat(progress * progress)
                let colorIdx = Int(hash(i, 6) * 4)
                let c = colors[colorIdx]
                let coreR = 2.0 + hash(i, 7) * 3.6
                let alpha = 0.9 * (1 - progress)   // 平滑淡出（v2.0.133c：去掉 twinkle 闪烁）
                // 注：GraphicsContext 无 saveGState/restoreGState（那是 CGContext API），保存/恢复 transform 等效
                let savedTransform = ctx.transform
                ctx.translateBy(x: x, y: y)
                // 光晕（大圆低透明）只对半数粒子绘制（hash<0.5），减半 fill 次数
                if hash(i, 8) < 0.5 {
                    ctx.scaleBy(x: CGFloat(coreR * 3.5), y: CGFloat(coreR * 3.5))
                    ctx.fill(unitDot, with: .color(c.opacity(alpha * 0.22)))
                    ctx.transform = savedTransform
                    ctx.translateBy(x: x, y: y)
                }
                // 核心（小圆高透明）：缩放 1 倍单位圆（CGFloat 显式转换——GraphicsContext 参数是 CGFloat，Double 直传会类型错误）
                ctx.scaleBy(x: CGFloat(coreR), y: CGFloat(coreR))
                ctx.fill(unitDot, with: .color(c.opacity(alpha)))
                ctx.transform = savedTransform
            }
        }
    }
}

/// 多彩光晕圆球：TimelineView 驱动 AngularGradient 呼吸（复用 Siri 发光配色：蓝紫粉红淡雅）。
/// 单击 → 展开输入框；长按 → 语音转文字（球保持特效）。
/// ⚠️ 手势用 ExclusiveGesture(LongPress, Tap) 互斥（v2.0.98 SIGTRAP 教训：勿叠加 onTap+onLongPress）。
struct SiriBallView: View {
    var isRecording: Bool = false
    var voiceMode: Bool = false
    var transcribing: Bool = false   // v2.0.129：转写中显示转圈
    // v3.0.12：思考球——流式回答中 orbits(点点旋转) / 空闲 ring(缓慢脉动)
    var thinking: Bool = false
    var onTap: () -> Void = {}
    var onLongPress: () -> Void = {}

    var body: some View {
        // v2.0.132 优化：球呼吸降到 30fps（TimelineView(.animation) 每帧重绘 AngularGradient+blur 常驻开销大；30fps 肉眼无差）
        // v2.0.133g：schedule 提为显式类型变量（同 FullScreenBurst，防 CI 泛型推断失败）
        let schedule: AnimationTimelineSchedule = .animation(minimumInterval: 1.0 / 30.0)
        TimelineView(schedule) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // v2.0.132：语音激活（录音/转写中）→ 珊瑚红渐变 + 加速呼吸（一眼可辨）；
            // 默认 Siri 蓝紫粉淡雅
            let active = isRecording || transcribing
            let breathe = active
                ? 0.5 + 0.35 * (sin(t * 4.5) + 1) / 2    // 语音中呼吸加速
                : 0.35 + 0.30 * (sin(t * 2.2) + 1) / 2
            let glowColors: [Color] = active
                ? [.red.opacity(0.65 * breathe), .orange.opacity(0.55 * breathe),
                   .pink.opacity(0.55 * breathe), .red.opacity(0.65 * breathe)]
                : [.blue.opacity(0.55 * breathe), .indigo.opacity(0.5 * breathe),
                   .pink.opacity(0.5 * breathe), .purple.opacity(0.42 * breathe),
                   .blue.opacity(0.55 * breathe)]
            let bodyColors: [Color] = active
                ? [.red.opacity(0.92 * breathe), .orange.opacity(0.85 * breathe),
                   .pink.opacity(0.85 * breathe), .red.opacity(0.92 * breathe)]
                : [.blue.opacity(0.85 * breathe), .indigo.opacity(0.8 * breathe),
                   .pink.opacity(0.8 * breathe), .purple.opacity(0.72 * breathe),
                   .blue.opacity(0.85 * breathe)]
            ZStack {
                // 外发光（虚化光晕）v2.0.139 性能：blur 8→6（blur 开销随半径超线性，视觉几乎无差）
                Circle()
                    .fill(
                        AngularGradient(
                            colors: glowColors,
                            center: .center
                        )
                    )
                    .blur(radius: 6)
                    .frame(width: 84, height: 84)
                // 主体球（v2.0.130：72pt = 与首页"你好，我是轻聊" Logo 同尺寸）
                Circle()
                    .fill(
                        AngularGradient(
                            colors: bodyColors,
                            center: .center
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1.2)
                    )
                    .shadow(color: (active ? Color.red : Color.indigo).opacity(0.45 * breathe), radius: 14)
                // 中心：录音风格圆形波形 logo（声呐扩散波纹，v2.0.130 用户指定）+ 状态覆盖
                // 默认 = 波纹扩散动画（像录音 app 的圆形 logo）；录音中 = 波形+松开结束；转写中 = 转圈
                if transcribing {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 24, height: 24)
                } else if isRecording {
                    VStack(spacing: 3) {
                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .white.opacity(0.5), radius: 3)
                        Text("松开结束")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                } else {
                    // v3.0.12：思考球粒子画布——流式/思考中 orbits(点点旋转)，空闲 ring(缓慢脉动)
                    OrbCanvasView(mode: thinking ? .orbits : .ring, size: 60)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: 92, height: 92)
        .contentShape(Circle())
        .gesture(
            LongPressGesture(minimumDuration: 0.4)
                .exclusively(before: TapGesture())
                .onEnded { value in
                    switch value {
                    case .first:
                        onLongPress()
                    case .second:
                        onTap()
                    }
                }
        )
        // 录音中：红圈脉冲提示
        .overlay {
            if isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.6), lineWidth: 2.5)
                    .frame(width: 92, height: 92)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - v2.0.96 Hermes 捷径面板（官方斜杠命令 + 功能注释，点击填充输入框）

struct HermesShortcutSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    // 官方命令（hermes-agent 文档）：命令 + 中文功能注释
    private let items: [(cmd: String, desc: String)] = [
        ("/help", "查看全部可用命令"),
        ("/new", "开启全新会话（清空上下文）"),
        ("/model deepseek-v4-flash", "切换模型（如 deepseek-v4-flash）"),
        ("/compress", "压缩当前上下文，节省 token"),
        ("/memory", "查看与管理 AI 记忆"),
        ("/skills", "浏览、搜索、安装技能"),
        ("/skill <名称>", "加载指定技能到当前会话"),
        ("/cron", "定时任务管理（查看/创建/暂停）"),
        ("/voice on", "开启语音对话模式"),
        ("/voice off", "关闭语音模式"),
        ("/undo", "撤销上一轮对话"),
        ("/title <名称>", "给当前会话命名"),
        ("/usage", "查看 Token 用量统计"),
        ("/status", "查看会话与系统状态"),
        ("/personality <名称>", "切换 AI 人格"),
        ("/reasoning high", "设置思考深度（none/low/medium/high）"),
        ("/background <任务>", "后台运行长任务（不阻塞对话）"),
        ("/queue <任务>", "排队等待下一轮处理"),
        ("/fast", "切换优先快速处理"),
        ("/resume <名称>", "恢复历史会话"),
        ("/sethome", "把当前聊天设为默认投递位置"),
        ("/update", "更新 Hermes 到最新版"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(items, id: \.cmd) { item in
                    Button {
                        onPick(item.cmd)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Text(item.cmd)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                            Text(item.desc)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle("Hermes 捷径")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                }
            }
        }
    }
}

// MARK: - v2.0.43 快捷指令面板（常用 prompt 模板，点击填充输入框）

struct QuickPromptSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    // v3.0.6 fix：知识库快捷指令仅本地 AI 显示（云端无）；默认含，ChatView 按模式传
    var includeKB: Bool = true

    private var prompts: [(icon: String, name: String, prompt: String)] {
        var list: [(icon: String, name: String, prompt: String)] = [
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
        // v2.0.104b：知识库快捷指令（@知识库 前缀触发知识库检索问答）——仅本地 AI 有
        if includeKB {
            list.append(("books.vertical.fill", "知识库", "@知识库 "))
        }
        return list
    }

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

// MARK: - v2.0.87d markdown 表格视图（表头加粗 + 斑马纹 + 横向滚动）
// v2.0.87m：统一列宽（按每列最大内容宽度，列对齐不再错位）

private struct MarkdownTableView: View {
    let rows: [[String]]

    /// 每列统一宽度（按该列最长内容估宽，中文 12pt 约 13px/字）
    private var colWidths: [CGFloat] {
        guard let first = rows.first else { return [] }
        return first.indices.map { c in
            let maxLen = rows.map { $0.indices.contains(c) ? $0[c].count : 0 }.max() ?? 0
            return max(56, min(CGFloat(maxLen) * 13 + 22, 160))
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { c in
                            Text(rows[r][c])
                                .font(.system(size: 12, weight: r == 0 ? .semibold : .regular))
                                .foregroundStyle(r == 0 ? Color.primary : Color.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(width: colWidths.indices.contains(c) ? colWidths[c] : 80, alignment: .leading)
                                .background(r == 0
                                            ? Color.accentColor.opacity(0.08)
                                            : (r % 2 == 0 ? Color.primary.opacity(0.03) : Color.clear))
                        }
                    }
                    Divider().overlay(Color.primary.opacity(0.07))
                }
            }
            .padding(8)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.vertical, 2)
        }
        .textSelection(.enabled)
    }
}

// MARK: - v2.0.87q 文件消息微信风格卡片（类型图标 + 文件名 + 状态）

struct FileMessageInfo {
    let name: String
    let type: String      // pdf / doc / xlsx / txt / img / other
    let status: String
    let failed: Bool
}

extension MessageBubble {
    /// 解析文件消息文本（[文件: name]（状态）/[PDF: name]（状态）…）
    private func parseFileMessage(_ content: String) -> FileMessageInfo? {
        guard content.hasPrefix("[文件:") || content.hasPrefix("[PDF:") || content.hasPrefix("[图片:") else { return nil }
        // 提取方括号内文件名（v2.0.102：按实际前缀长度截断——[文件:/[图片: 4 字符，[PDF: 5 字符，原 drop 3 会把冒号带进文件名）
        let drop: Int = content.hasPrefix("[PDF:") ? 5 : 4
        let rest = content.dropFirst(drop)
        guard let end = rest.firstIndex(of: "]") else { return nil }
        let name = String(rest[..<end]).trimmingCharacters(in: .whitespaces)
        // 提取括号内状态
        var status = ""
        var failed = false
        if let s = content.firstIndex(of: "（"), let e = content.lastIndex(of: "）") {
            status = String(content[content.index(after: s)..<e])
            failed = status.contains("失败")
        }
        let lower = name.lowercased()
        let type: String
        if lower.hasSuffix(".pdf") { type = "pdf" }
        else if lower.hasSuffix(".xlsx") || lower.hasSuffix(".xls") || lower.hasSuffix(".csv") { type = "xlsx" }
        else if lower.hasSuffix(".doc") || lower.hasSuffix(".docx") { type = "doc" }
        else if lower.hasSuffix(".txt") || lower.hasSuffix(".md") || lower.hasSuffix(".log") || lower.hasSuffix(".json") { type = "txt" }
        else { type = "other" }
        return FileMessageInfo(name: name, type: type,
                               status: status.isEmpty ? (failed ? "上传失败" : "已上传") : status,
                               failed: failed)
    }
}

/// 微信风格文件卡片（用户气泡内：图标块 + 文件名 + 状态）
struct FileMessageCard: View {
    let file: FileMessageInfo

    private var icon: String {
        switch file.type {
        case "pdf": return "doc.richtext.fill"
        case "xlsx": return "tablecells.fill"
        case "doc": return "doc.text.fill"
        case "txt": return "doc.plaintext.fill"
        case "img": return "photo.fill"
        default: return "doc.fill"
        }
    }

    private var color: Color {
        switch file.type {
        case "pdf": return .red
        case "xlsx": return .green
        case "doc": return .blue
        case "txt": return .gray
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.22))
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if file.failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9))
                    }
                    Text(file.status)
                        .font(.system(size: 10))
                        .foregroundStyle(file.failed ? Color.red.opacity(0.9) : Color.white.opacity(0.75))
                }
            }
            Spacer(minLength: 4)
            Image(systemName: file.failed ? "arrow.clockwise" : "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(file.failed ? Color.red.opacity(0.8) : Color.white.opacity(0.55))
        }
        .padding(10)
        .frame(maxWidth: 240)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - v2.0.92 会话分享卡片（ImageRenderer 渲染为图片，微信/系统分享）

struct SessionCardView: View {
    let rows: [(role: String, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("轻聊 AI 会话")
                    .font(.system(size: 17, weight: .bold))
            }
            Text(formattedDate)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            Divider()
                .padding(.vertical, 10)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.role == "user" ? "我" : "AI")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(row.role == "user" ? Color.blue : Color.indigo, in: Capsule())
                    Text(row.text)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08))
        )
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: Date())
    }
}
