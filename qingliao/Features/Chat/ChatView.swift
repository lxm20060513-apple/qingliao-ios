import SwiftUI
import PhotosUI

// MARK: - 聊天页（微信风格：AI 灰气泡左侧 / 用户深蓝气泡右侧，头像在气泡外）

struct ChatView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream
    @Environment(KeyboardObserver.self) private var kb

    @State private var inputText = ""
    @FocusState private var inputFocus: Bool
    @State private var sentOK = false   // ✅送达提示条
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingImageData: String?

    private let modelName = "deepseek-v4-flash"
    private let provider = "opencode"

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "聊天", subtitle: "在线")
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
            ChatInputBar(text: $inputText, focused: $inputFocus, streaming: stream.isStreaming) {
                send()
            } onStop: {
                stream.stop(auth: auth)
            } onPickAttachment: {
                showPhotoPicker = true
            }
            // 键盘弹出：输入框紧贴键盘上方（Dock 已隐藏）；收起：留 100pt 避让悬浮 Dock
            .padding(.bottom, kb.isVisible ? kb.height + 10 : 100)
        }
        .animation(.easeOut(duration: 0.22), value: kb.height)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
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
                        ForEach(chat.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                        if stream.isStreaming {
                            MessageBubble(
                                message: ChatMessage(role: "assistant", content: stream.content, timestamp: nil)
                            )
                            .id("streaming")
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

    /// ✅送达提示条（仅成功时显示，2.5s 后消失）
    private func showSentOK() {
        withAnimation(.easeOut(duration: 0.3)) { sentOK = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { sentOK = false }
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

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPickAttachment) {
                Image(systemName: "paperclip")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)

            TextField("输入消息...", text: $text, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(.vertical, 7)
                .padding(.horizontal, 2)
                .focused($focused)

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
