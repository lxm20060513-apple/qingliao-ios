import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import AVFoundation
import Speech

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
    // 语音输入（按住说话 → SFSpeechRecognizer 转写）
    @State private var isRecording = false
    @State private var voiceBusy = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var showModelSheet = false   // 模型快速切换
    @State private var showAttachmentMenu = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingImageData: String?

    // 模型可从设置页选择（UserDefaults 持久化，默认 deepseek-v4-flash）
    private var modelName: String {
        UserDefaults.standard.string(forKey: "qingliao_model") ?? "deepseek-v4-flash"
    }
    private let provider = "opencode"

    /// 头部模型快速切换按钮（独立表达式，避免类型检查超时）
    private var modelHeaderButton: AnyView {
        AnyView(
            Button {
                showModelSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                    Text(modelName)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "聊天",
                       subtitle: serverOnline == nil ? "检测中" : (serverOnline == true ? "在线" : "离线"),
                       trailing: modelHeaderButton,
                       showStatus: true,
                       statusColor: serverOnline == true ? .green : (serverOnline == false ? .red : .gray))
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
            ChatInputBar(text: $inputText, focused: $inputFocus, streaming: stream.isStreaming,
                         isRecording: isRecording,
                         onVoiceStart: { startVoice() },
                         onVoiceEnd: { endVoice() }) {
                send()
            } onStop: {
                stream.stop(auth: auth)
            } onPickAttachment: {
                showAttachmentMenu = true
            }
            // 键盘弹出：输入框紧贴键盘上方（Dock 已隐藏）；收起：留 100pt 避让悬浮 Dock
            .padding(.bottom, kb.isVisible ? kb.height + 10 : 100)
        }
        .animation(.easeOut(duration: 0.22), value: kb.height)
        .confirmationDialog("添加附件", isPresented: $showAttachmentMenu, titleVisibility: .visible) {
            Button("图片") { showPhotoPicker = true }
            Button("文件 (PDF / Word / Excel / 文本)") { showFileImporter = true }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
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
                if chat.messages.isEmpty && !stream.isStreaming {
                    // 首次进入欢迎占位
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
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { idx, msg in
                            // 相邻消息间隔 >5 分钟：插入居中时间分隔（微信式）
                            if idx > 0,
                               let prevTs = chat.messages[idx - 1].timestamp,
                               let curTs = msg.timestamp,
                               curTs - prevTs > 300_000 {
                                timeDivider(curTs)
                            }
                            MessageBubble(message: msg) {
                                regenerate(at: msg.id)
                            }
                            .id(msg.id)
                            // 气泡出现动效：淡入 + 轻微上移（灵动）
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                                    removal: .opacity))
                            .animation(.spring(duration: 0.3, bounce: 0.2), value: chat.messages.count)
                        }
                        if stream.isStreaming {
                            if stream.content.isEmpty {
                                // 思考中动画（三点跳动）
                                HStack(alignment: .top, spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 30, height: 30)
                                    TypingIndicator()
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 12)
                                        .background(Color(uiColor: .systemGray5))
                                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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
                .presentationDetents([.medium])
        }
    }

    /// 思考中动画（三点跳动）
    struct TypingIndicator: View {
        @State private var animating = false
        var body: some View {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 6, height: 6)
                        .offset(y: animating ? -3 : 3)
                        .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.14), value: animating)
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
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = pendingImageData
        guard (!text.isEmpty || img != nil), !stream.isStreaming else { return }
        inputText = ""
        pendingImage = nil
        pendingImageData = nil

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
                }
                // 保存会话到后端（会话记录同步）
                Task { await chat.saveToServer(auth: auth) }
            }
        }
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

    // MARK: - 语音输入（按住说话 → 录音 → SFSpeechRecognizer 转写填入输入框）

    private func startVoice() {
        guard !voiceBusy, !isRecording else { return }
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return }
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
    var onRegenerate: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 48)
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
                }
                if !message.content.isEmpty {
                    Text(message.isUser ? AttributedString(message.content) : markdownText)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(message.isUser ? .white : .primary)
                        .textSelection(.enabled)   // 长按选中复制（参考 web 版排版体验）
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            message.isUser
                                ? Color(red: 0.13, green: 0.22, blue: 0.45)                 // 深蓝 navy 气泡
                                : Color(uiColor: .systemGray5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            }
            .frame(maxWidth: 290, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        // 长按：复制（全部消息）/ 重新生成（AI 消息）
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            if !message.isUser {
                Button {
                    onRegenerate()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    /// AI 消息 markdown 渲染（解析失败回退纯文本——流式中途未闭合语法常见）
    private var markdownText: AttributedString {
        (try? AttributedString(markdown: message.content)) ?? AttributedString(message.content)
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
                TextField("输入消息...", text: $text, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 2)
                    .focused($focused)
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
