import SwiftUI

// MARK: - 会话页（真实会话列表 + 滑动删除 + 点击进入聊天）

struct SessionsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat

    @State private var sessions: [ChatSession] = []
    @State private var isLoading = false
    @State private var errorText: String?
    var onOpenSession: (() -> Void)? = nil   // 切到聊天 tab

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "会话", trailing: AnyView(addButton))
            if isLoading && sessions.isEmpty {
                Spacer()
                ProgressView()
                    .tint(.secondary)
                Spacer()
            } else if let err = errorText, sessions.isEmpty {
                Spacer()
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("重试") { Task { await load() } }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        BotCard()
                        if sessions.isEmpty {
                            Text("暂无会话记录")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 30)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(sessions) { s in
                                    SessionRow(session: s) {
                                        chat.load(s)
                                        onOpenSession?()
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            delete(s)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .glassListCard()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 90)
                }
                .refreshable {
                    await load()
                }
            }
        }
        .task { await load() }
    }

    private var addButton: some View {
        Button {
            chat.newSession()
            onOpenSession?()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            let j = try await auth.json("/api/sessions/list")
            let raw = (j["sessions"] as? [Any] ?? [])
            sessions = raw.compactMap { ChatSession.parse($0 as? [String: Any] ?? [:]) }
        } catch {
            errorText = "加载失败，请检查连接"
        }
        isLoading = false
    }

    private func delete(_ s: ChatSession) {
        // 本地先移除，再同步到后端（merge deleted）
        withAnimation {
            sessions.removeAll { $0.id == s.id }
        }
        if chat.sessionId == s.id {
            chat.newSession()
        }
        Task {
            do {
                _ = try await auth.json("/api/sessions/merge", method: "POST", body: [
                    "sessions": [] as [Any],
                    "deleted": [s.id]
                ])
            } catch {
                // 后端同步失败时回滚恢复
                if !sessions.contains(where: { $0.id == s.id }) {
                    sessions.append(s)
                    sessions.sort { ($0.lastTime ?? 0) > ($1.lastTime ?? 0) }
                }
            }
        }
    }
}

// MARK: - 机器人卡

struct BotCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("M")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("机器人 main")
                    .font(.system(size: 15, weight: .semibold))
                Text("deepseek/deepseek-v4-flash")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("在线")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
        .padding(13)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.14), Color.indigo.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 0.8)
        )
    }
}

// MARK: - 会话行

struct SessionRow: View {
    let session: ChatSession
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.18), Color.indigo.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.blue.opacity(0.8))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title.isEmpty ? "新对话" : session.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(session.lastMessageText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.relativeTime)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
