import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import AVFoundation
import Speech

// MARK: - v2.0.50 滚动位置检测（替代 .scrollPosition，DockVisibility 用）
// .scrollPosition 在 TabView 隐藏页内容清空时是已知崩溃点（SIGTRAP），
// 换 GeometryReader + PreferenceKey：滚动时上报内容区 minY，取负后语义同 scrollPos.y

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
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

struct ChatView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream
    @Environment(KeyboardObserver.self) private var kb

    @State private var inputText = ""
    @FocusState private var inputFocus: Bool
    @State private var sentOK = false
    @State private var serverOnline: Bool?   // 服务器连接状态（真实绿点）
    // v2.0.36：引用回复 / 图片查看器 / 导出
    @State private var quotedMessage: ChatMessage?
    @State private var viewerPayload: ImageViewPayload?
    @State private var showMoreMenu = false
    @State private var showExporter = false
    @State private var exportText = ""
    @State private var showVoiceDenied = false   // v2.0.36 录音权限被拒提示
    @State private var clearing = false          // v2.0.40 清空会话两步走标志
    // v2.0.43：快捷指令 / 搜索定位高亮
    @State private var showQuickPrompts = false
    @State private var highlightMessageID: String?
    // v2.0.46：隐藏 Dock 栏开关（开启时输入框贴底）
    @AppStorage("qingliao_hide_dock") private var hideDock = false
    // 语音输入（按住说话 → SFSpeechRecognizer 转写）
    @State private var isRecording = false
    @State private var voiceBusy = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var showModelSheet = false   // 模型快速切换
    @State private var showAttachmentMenu = false
    // 大爆炸（BigBang）文本炸开
    @State private var bigBangPayload: BigBangPayload?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCameraPicker = false   // v2.0.38 拍照输入
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingImageData: String?

    // 模型/提供商可从模型管理面板选择（UserDefaults 持久化）
    // v2.0.48：改 @AppStorage——computed property 无观察机制，
    // 设置页切换模型后聊天页头部不刷新（模型实际生效但显示旧名）
    @AppStorage("qingliao_model") private var modelName = "deepseek-v4-flash"
    @AppStorage("qingliao_provider") private var provider = "opencode"

    /// 头部状态文案/颜色（独立计算属性，避免 body 内嵌套三元）
    private var headerSubtitle: String {
        serverOnline == nil ? "检测中" : (serverOnline == true ? "在线" : "离线")
    }
    private var headerColor: Color {
        serverOnline == true ? .green : (serverOnline == false ? .red : .gray)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "聊天",
                       subtitle: headerSubtitle,
                       trailing: AnyView(
                           Button {
                               showMoreMenu = true
                           } label: {
                               Image(systemName: "ellipsis.circle")
                                   .font(.system(size: 17, weight: .semibold))
                                   .foregroundStyle(Color.accentColor)
                           }
                           .buttonStyle(.plain)
                       ),
                       showStatus: true,
                       statusColor: headerColor)
            .confirmationDialog("聊天操作", isPresented: $showMoreMenu, titleVisibility: .visible) {
                Button("导出会话记录") {
                    exportText = chat.exportText()
                    showExporter = true
                }
                // v2.0.43：上下文信息 + 一键压缩
                Button("上下文：约 \(chat.contextInfo.tokens) tokens · \(chat.contextInfo.count) 条") {}
                Button("压缩上下文（保留最近 20 条）") {
                    if chat.compressContext() {
                        Task { await chat.saveToServer(auth: auth) }
                    }
                }
                Button("清空本会话消息", role: .destructive) {
                    // v2.0.40：两步走清空——先切欢迎页分支（列表立即卸载，数据未动），
                    // 下一帧再清数据。列表销毁与数据清空完全错开，杜绝同帧崩溃。
                    clearing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(nil) { chat.clearMessages() }
                        clearing = false
                    }
                    Task { await chat.saveToServer(auth: auth) }
                }
                Button("取消", role: .cancel) {}
            }
            if sentOK {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("已送达 · 消息已发出")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .transition(.opacity)
            }
            messageList
            // 图片预览条（选图后显示）
            if let img = pendingImage {
                HStack(spacing: 10) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("图片已选择，发送后 AI 可识别")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        pendingImage = nil
                        pendingImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            // 内联附件面板（类微信 + 面板：点击回形针展开）
            if showAttachmentMenu {
                HStack(spacing: 26) {
                    attachButton("photo.on.rectangle", "图片", Color.blue) { showPhotoPicker = true }
                    attachButton("doc.fill", "文件", Color.indigo) { showFileImporter = true }
                    // v2.0.43：快捷指令（常用 prompt 模板）
                    attachButton("bolt.fill", "指令", Color.orange) { showQuickPrompts = true }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // v2.0.36：引用回复条（发送后自动清除）
            if let q = quotedMessage {
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text(String(q.content.prefix(60)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        quotedMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            ChatInputBar(text: $inputText,
                         focused: $inputFocus,
                         streaming: stream.isStreaming,
                         onSend: { send() },
                         onStop: { stream.stop(auth: auth) },
                         onPickAttachment: {
                             withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                 showAttachmentMenu.toggle()
                             }
                         },
                         onCamera: { showCameraPicker = true },
                         isRecording: isRecording,
                         onVoiceStart: { startVoice() },
                         onVoiceEnd: { endVoice() })
            // v2.0.37：键盘弹出时输入框贴键盘顶部（绝对坐标换算，0 空隙）；
            // v2.0.46：隐藏 Dock 栏开关开启时输入框贴底（不留 Dock 避让），否则留 86pt 避让贴底 Dock
            .padding(.bottom, kb.isVisible
                     ? max(0, UIScreen.main.bounds.height - kb.topY)
                     : (hideDock ? 0 : 86))
        }
        .animation(.easeOut(duration: 0.22), value: kb.height)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        // v2.0.38：拍照输入（拍完进图片预览条，确认后发送）
        .sheet(isPresented: $showCameraPicker) {
            CameraPicker { img in
                pendingImage = img
                pendingImageData = compressImage(img)
            }
        }
        // v2.0.43：快捷指令面板（点击填充输入框）
        .sheet(isPresented: $showQuickPrompts) {
            QuickPromptSheet { prompt in
                inputText = prompt
                showAttachmentMenu = false
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .plainText,
                                            UTType(filenameExtension: "docx") ?? .data,
                                            UTType(filenameExtension: "xlsx") ?? .data]) { result in
            if case .success(let url) = result {
                sendFile(url)
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    pendingImage = img
                    pendingImageData = compressImage(img)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // v2.0.40：clearing 期间直接显示欢迎页（列表已卸载，数据稍后清空）
                if (chat.messages.isEmpty || clearing) && !stream.isStreaming {
                    // 首次进入欢迎占位（v2.0.39：.id 强制与消息列表分支区分身份，
                    // 清空会话时列表↔欢迎页切换不再复用视图身份导致崩溃）
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("你好，我是轻聊")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("输入消息与 AI 对话")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                    .id("welcome")
                } else {
                    // v2.0.40：LazyVStack → VStack（懒加载在批量移除时有复用状态残留，
                    // 普通 VStack 全量渲染，移除只是简单数组变化，彻底绕开崩溃）
                    VStack(spacing: 10) {
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { idx, msg in
                            // 相邻消息间隔 >5 分钟：插入居中时间分隔（微信式）
                            if idx > 0,
                               let prevTs = chat.messages[idx - 1].timestamp,
                               let curTs = msg.timestamp,
                               curTs - prevTs > 300_000 {
                                timeDivider(curTs)
                            }
                            MessageBubble(message: msg,
                                          isHighlighted: msg.id == highlightMessageID) {
                                regenerate(at: msg.id)
                            } onBigBang: {
                                bigBangPayload = BigBangPayload(text: msg.content)
                            } onQuote: {
                                // v2.0.36：引用回复（点击回复时输入框聚焦）
                                quotedMessage = msg
                                inputFocus = true
                            } onDelete: {
                                // v2.0.36：单条删除（按索引精确删除，防同内容 hash id 误删）
                                if let idx = chat.messages.firstIndex(where: { $0.timestamp == msg.timestamp && $0.role == msg.role && $0.content == msg.content }) {
                                    withAnimation { chat.messages.remove(at: idx) }
                                    Task { await chat.saveToServer(auth: auth) }
                                }
                            } onShare: {
                                shareText(msg.content)
                            } onImageTap: {
                                if let img = dataURLImage(msg.imageDataURL ?? "") {
                                    viewerPayload = ImageViewPayload(image: img)
                                }
                            }
                            .id(msg.id)
                            // 气泡出现动效：淡入 + 轻微上移（灵动）
                            // v2.0.38：去掉 .animation(value: messages.count)——
                            // 批量清空（清空会话/新建会话）时全 cell 同时移除的 spring 动画曾导致闪退
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                                    removal: .opacity))
                        }
                        if stream.isStreaming {
                            if stream.content.isEmpty {
                                // 思考中动画（三点跳动，气泡加大版）
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 38, height: 38)
                                    // v2.0.35：去掉"思考中"文字（用户要求），保留三点跳动动画
                                    TypingIndicator()
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 15)
                                        .background(Color(uiColor: .systemGray5))
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .frame(minHeight: 44)
                                    Spacer(minLength: 48)
                                }
                                .id("streaming")
                                .transition(.opacity)
                            } else {
                                MessageBubble(
                                    message: ChatMessage(role: "assistant", content: stream.content, timestamp: nil)
                                )
                                .id("streaming")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .id("messages")   // v2.0.39：与欢迎页分支区分身份
                }
            }
            // v2.0.50：.scrollPosition 在隐藏页内容清空时是已知崩溃点（新建会话=TabView
            // 隐藏页清空→scrollPos 更新异常→SIGTRAP）→ 换 GeometryReader + PreferenceKey 检测滚动
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                            value: geo.frame(in: .named("scrollspace")).minY)
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { minY in
                DockVisibility.shared.update(-minY)
            }
            // v2.0.43：搜索定位——滚动到命中消息并高亮 2 秒
            .onChange(of: chat.highlightTarget?.content) { _, _ in
                guard let t = chat.highlightTarget,
                      let idx = chat.indexOfMessage(role: t.role, contentPrefix: t.content) else { return }
                let mid = chat.messages[idx].id
                highlightMessageID = mid
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(mid, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) { highlightMessageID = nil }
                }
            }
            // 滚动消息区即收起键盘（微信式）
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture {
                inputFocus = false
            }
            .onChange(of: chat.messages.count) {
                scrollBottom(proxy)
            }
            .onChange(of: stream.content) {
                scrollBottom(proxy)
            }
        }
        .task {
            // 服务器连接状态检测（真实绿点）
            let r = await auth.testConnection(server: auth.serverURL)
            serverOnline = r.hasPrefix("✅")
        }
        .sheet(isPresented: $showModelSheet) {
            ModelSheet(current: modelName)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $bigBangPayload) { payload in
            BigBangView(text: payload.text)
        }
        // v2.0.36：图片大图查看器
        .fullScreenCover(item: $viewerPayload) { p in
            ImageViewer(image: p.image)
        }
        // v2.0.36：导出会话记录
        .fileExporter(isPresented: $showExporter,
                      document: ChatLogDocument(text: exportText),
                      contentType: .plainText,
                      defaultFilename: "轻聊会话") { _ in }
        // v2.0.36：录音权限被拒提示
        .alert("无法使用语音输入", isPresented: $showVoiceDenied) {
            Button("去设置", role: .cancel) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("麦克风权限被拒绝，请在系统设置中允许轻聊使用麦克风")
        }
    }

    /// 思考中动画（三点跳动）
    struct TypingIndicator: View {
        @State private var animating = false
        var body: some View {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .offset(y: animating ? -4 : 4)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: animating)
                }
            }
            .onAppear { animating = true }
        }
    }

    /// 相邻消息间隔 >5 分钟的居中时间分隔
    private func timeDivider(_ ts: Double) -> some View {
        let d = Date(timeIntervalSince1970: ts / 1000)
        let text: String
        if Calendar.current.isDateInToday(d) {
            text = d.formatted(date: .omitted, time: .shortened)
        } else if Calendar.current.isDateInYesterday(d) {
            text = "昨天 " + d.formatted(date: .omitted, time: .shortened)
        } else {
            text = d.formatted(date: .abbreviated, time: .shortened)
        }
        return Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private func scrollBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if stream.isStreaming {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = chat.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - 发送

    private func send() {
        var text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = pendingImageData
        guard (!text.isEmpty || img != nil), !stream.isStreaming else { return }
        // v2.0.36：引用回复（markdown 引用块注入，AI 可见上下文）
        if let q = quotedMessage, !text.isEmpty {
            let quoted = q.content.replacingOccurrences(of: "\n", with: "\n> ")
            text = "> " + quoted + "\n\n" + text
        }
        inputText = ""
        quotedMessage = nil
        pendingImage = nil
        pendingImageData = nil
        // v2.0.36：发送触感反馈
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        chat.append(.local(role: "user", content: text, imageDataURL: img))
        let history = chat.historyPayload()

        Task {
            await stream.start(
                auth: auth,
                sessionId: chat.sessionId,
                model: modelName,
                provider: provider,
                messages: history
            ) { success, error in
                if !success {
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)")
                } else {
                    chat.upsertAssistant(stream.content)
                    showSentOK()
                    // v2.0.36：App 退后台时 AI 回复完成发本地通知
                    if UIApplication.shared.applicationState != .active {
                        NotificationHelper.notify(title: "轻聊", body: "AI 回复完成，点击查看")
                    }
                }
                // 保存会话到后端（会话记录同步）
                Task { await chat.saveToServer(auth: auth) }
            }
        }
    }

    /// v2.0.36：系统分享面板（转发消息到微信/备忘录等）
    private func shareText(_ text: String) {
        guard !text.isEmpty else { return }
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    /// v2.0.36：图片 dataURL → UIImage（大图查看用；与 MessageBubble 同逻辑）
    private func dataURLImage(_ urlStr: String) -> UIImage? {
        guard let comma = urlStr.firstIndex(of: ","),
              let data = Data(base64Encoded: String(urlStr[urlStr.index(after: comma)...])),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    /// 发送 PDF 文件对话（PDFKit 提取文本拼进消息，AI 直接读内容）
    private func sendPDF(_ url: URL) {
        guard !stream.isStreaming else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let rawText = extractPDFText(from: url) ?? ""
        let truncated = String(rawText.prefix(12000))
        let content = truncated.isEmpty
            ? "[PDF 文档: \(name)]"
            : "[PDF 文档: \(name)]\n\(truncated)"
        chat.append(.local(role: "user", content: content))
        let history = chat.historyPayload()
        Task {
            await stream.start(auth: auth, sessionId: chat.sessionId, model: modelName,
                               provider: provider, messages: history) { success, error in
                if !success {
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)")
                } else {
                    chat.upsertAssistant(stream.content)
                    showSentOK()
                    // v2.0.36：App 退后台时 AI 回复完成发本地通知
                    if UIApplication.shared.applicationState != .active {
                        NotificationHelper.notify(title: "轻聊", body: "AI 回复完成，点击查看")
                    }
                }
                Task { await chat.saveToServer(auth: auth) }
            }
        }
    }

    /// 发送任意文档：txt 直接读文本（AI 可读）；Word/Excel 无法本地提取 → 降级上传 NAS 文件管理
    private func sendFile(_ url: URL) {
        guard !stream.isStreaming else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()

        // 文本类：直接读入对话
        if ["txt", "md", "log", "json", "csv"].contains(ext) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let truncated = String(text.prefix(12000))
                let content = "[文本文件: \(name)]\n\(truncated)"
                chat.append(.local(role: "user", content: content))
                let history = chat.historyPayload()
                Task {
                    await stream.start(auth: auth, sessionId: chat.sessionId, model: modelName,
                                       provider: provider, messages: history) { success, error in
                        if !success {
                            chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)")
                        } else {
                            chat.upsertAssistant(stream.content)
                            showSentOK()
                        }
                        Task { await chat.saveToServer(auth: auth) }
                    }
                }
                return
            }
        }

        // PDF 走文本提取
        if ext == "pdf" {
            sendPDF(url)
            return
        }

        // Word/Excel：本地无法提取 → 降级上传 NAS 文件管理（relay 上行限 2KB 小文件）
        Task {
            let content: String
            if let data = try? Data(contentsOf: url), data.count < 2000 {
                if let j = try? await auth.uploadMultipart("/api/files/upload", fileName: name, data: data),
                   (j["ok"] as? Bool) == true {
                    content = "[文档: \(name)]（已上传 NAS 文件管理）"
                } else {
                    content = "[文档: \(name)]（上传失败，文件未解析）"
                }
            } else {
                content = "[文档: \(name)]（文件较大，请用 PWA 上传解析）"
            }
            chat.append(.local(role: "user", content: content))
            let history = chat.historyPayload()
            await stream.start(auth: auth, sessionId: chat.sessionId, model: modelName,
                               provider: provider, messages: history) { success, error in
                if !success {
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)")
                } else {
                    chat.upsertAssistant(stream.content)
                    showSentOK()
                }
                Task { await chat.saveToServer(auth: auth) }
            }
        }
    }

    /// PDFKit 提取文本（文本型 PDF 才有内容；扫描件无文字层返回空）
    private func extractPDFText(from url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        return doc.string
    }

    /// 重新生成：长按 AI 消息 → 删除该条及其后，重发
    private func regenerate(at id: String) {
        guard !stream.isStreaming,
              let idx = chat.messages.firstIndex(where: { $0.id == id }) else { return }
        chat.messages.removeSubrange(idx...)
        let history = chat.historyPayload()
        Task {
            await stream.start(auth: auth, sessionId: chat.sessionId, model: modelName,
                               provider: provider, messages: history) { success, error in
                if !success {
                    chat.upsertAssistant(stream.content.isEmpty ? "⚠️ \(error)" : stream.content + "\n\n⚠️ \(error)")
                } else {
                    chat.upsertAssistant(stream.content)
                    showSentOK()
                }
                Task { await chat.saveToServer(auth: auth) }
            }
        }
    }

    /// ✅送达提示条（仅成功时显示，2.5s 后消失）
    private func showSentOK() {
        withAnimation(.easeOut(duration: 0.3)) { sentOK = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { sentOK = false }
        }
    }

    /// 内联附件面板按钮（类微信 + 面板样式）
    private func attachButton(_ icon: String, _ name: String, _ color: Color,
                              action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { showAttachmentMenu = false }
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 语音输入（按住说话 → 录音 → SFSpeechRecognizer 转写填入输入框）

    private func startVoice() {
        guard !voiceBusy, !isRecording else { return }
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else {
                // v2.0.36：权限被拒明确提示（不再静默失败）
                DispatchQueue.main.async {
                    showVoiceDenied = true
                }
                return
            }
            DispatchQueue.main.async {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).m4a")
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
                do {
                    let rec = try AVAudioRecorder(url: url, settings: settings)
                    rec.record()
                    audioRecorder = rec
                    isRecording = true
                    inputFocus = false
                } catch {}
            }
        }
    }

    private func endVoice() {
        guard isRecording else { return }
        isRecording = false
        voiceBusy = true
        let url = audioRecorder?.url
        audioRecorder?.stop()
        audioRecorder = nil
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            voiceBusy = false
            return
        }
        transcribe(url)
    }

    private func transcribe(_ url: URL) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            voiceBusy = false
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let t = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    inputText = t
                    voiceBusy = false
                }
            } else if error != nil {
                DispatchQueue.main.async {
                    voiceBusy = false
                }
            }
        }
    }

    /// 图片压缩（PWA 同款：最长边 1280 / JPEG 0.72，超 900KB 降质）
    private func compressImage(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1280
        var w = image.size.width
        var h = image.size.height
        if max(w, h) > maxSide {
            let scale = maxSide / max(w, h)
            w *= scale
            h *= scale
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let resized = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var quality: CGFloat = 0.72
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > 900_000, quality > 0.25 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }
        guard let d = data else { return nil }
        return "data:image/jpeg;base64," + d.base64EncodedString()
    }
}

// MARK: - 消息气泡

struct MessageBubble: View {
    let message: ChatMessage
    var isHighlighted: Bool = false   // v2.0.43 搜索定位高亮
    var onRegenerate: () -> Void = {}
    var onBigBang: () -> Void = {}
    var onQuote: () -> Void = {}      // v2.0.36 引用回复
    var onDelete: () -> Void = {}     // v2.0.36 单条删除
    var onShare: () -> Void = {}      // v2.0.36 分享文本
    var onImageTap: () -> Void = {}   // v2.0.36 图片点击查看大图
    // v2.0.38：聊天字体大小（设置页可调，实时生效）
    @AppStorage("qingliao_font_size") private var fontSize = 14.0

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

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
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
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(isHighlighted ? Color(red: 0.20, green: 0.32, blue: 0.62) : Color(red: 0.13, green: 0.22, blue: 0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            // v2.0.43 搜索定位高亮边框
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(isHighlighted ? Color.accentColor : .clear, lineWidth: 2)
                            )
                    } else {
                        // AI 消息：代码块分段渲染（等宽 + 深色背景），其余 markdown
                        VStack(alignment: .leading, spacing: 6) {
                            // Range 重载（ForEach(0..<n)）无泛型歧义；渲染逻辑在 MessageBlockView
                            ForEach(0..<contentBlocks.count, id: \.self) { i in
                                MessageBlockView(block: contentBlocks[i])
                            }
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(isHighlighted ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        // v2.0.43 搜索定位高亮边框
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(isHighlighted ? Color.accentColor : .clear, lineWidth: 2)
                        )
                    }
                }
            }
            .frame(maxWidth: 366, alignment: message.isUser ? .trailing : .leading)   // v2.0.41 气泡加宽 350→366（贴红线/近满宽）

            if !message.isUser {
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

            // v2.0.38：拍照输入（相机按钮在语音按钮左边）
            Button(action: onCamera) {
                Image(systemName: "camera")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)

            // 语音输入：按住说话（类微信）
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.system(size: 17))
                .foregroundStyle(isRecording ? Color.red : Color.secondary)
                .padding(4)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                    if pressing && !isRecording {
                        onVoiceStart()
                    } else if !pressing && isRecording {
                        onVoiceEnd()
                    }
                }, perform: {})
                .animation(.easeOut(duration: 0.15), value: isRecording)

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
    let image: UIImage
}

struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var saved = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
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
            VStack {
                HStack {
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
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { saved = false }
                } label: {
                    Label(saved ? "已保存" : "保存到相册", systemImage: saved ? "checkmark" : "square.and.arrow.down")
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
