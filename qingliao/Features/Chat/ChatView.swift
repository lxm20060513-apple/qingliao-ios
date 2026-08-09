import SwiftUI

// MARK: - 聊天页（微信风格：AI 灰气泡左侧 / 用户深蓝气泡右侧，头像在气泡外）

struct ChatView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream
    @Environment(KeyboardObserver.self) private var kb

    @State private var inputText = ""
    @FocusState private var inputFocus: Bool
    @State private var sentOK = false   // ✅送达提示条

    private let modelName = "deepseek-v4-flash"
    private let provider = "opencode"

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "聊天", subtitle: "在线 · WebChat 直连 · \(displayServer)")
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
            ChatInputBar(text: $inputText, focused: $inputFocus, streaming: stream.isStreaming) {
                send()
            } onStop: {
                stream.stop(auth: auth)
            }
            // 键盘弹出：输入框紧贴键盘上方（Dock 已隐藏）；收起：留 100pt 避让悬浮 Dock
            .padding(.bottom, kb.isVisible ? kb.height + 10 : 100)
        }
        .animation(.easeOut(duration: 0.22), value: kb.height)
        .onChange(of: stream.isStreaming) { _, streaming in
            if !streaming, !stream.content.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) { sentOK = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { sentOK = false }
                }
            }
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
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

    private var displayServer: String {
        auth.serverURL.replacingOccurrences(of: "http://", with: "")
    }

    // MARK: - 发送

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !stream.isStreaming else { return }
        inputText = ""

        chat.append(.local(role: "user", content: text))
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
                }
            }
        }
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
                    Text("M")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
            }

            Text(message.content.isEmpty ? " " : message.content)
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
                .frame(maxWidth: 290, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

// MARK: - 液态玻璃输入栏

struct ChatInputBar: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var streaming: Bool
    var onSend: () -> Void
    var onStop: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button {} label: {
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
        // 键盘工具栏："完成"收起键盘（用户反馈键盘无法收回）
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focused = false }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}
