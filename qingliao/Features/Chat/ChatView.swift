import SwiftUI

// MARK: - 聊天页（微信风格）

struct ChatView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "聊天", subtitle: "在线 · WebChat 直连 · \(displayServer)")
            Spacer()
            Text("💬")
                .font(.system(size: 44))
            Text("你好，我是轻聊")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            Text("输入消息与 AI 对话")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer()
            ChatInputBar()
        }
    }

    private var displayServer: String {
        auth.serverURL.replacingOccurrences(of: "http://", with: "")
    }
}

// MARK: - 液态玻璃输入栏

struct ChatInputBar: View {
    @State private var text = ""

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

            Button {} label: {
                Image(systemName: "arrow.up")
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
        // 避开悬浮 Dock（Dock 高约 74pt + 间距），输入栏在 Dock 上方
        .padding(.bottom, 78)
    }
}
