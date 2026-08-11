import SwiftUI

// MARK: - 会话页（真实会话列表 + 滑动删除 + 点击进入聊天）

struct SessionsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat

    @State private var sessions: [ChatSession] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var deleteError: String?
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
                                    // 长按删除（滑动删除与 TabView 切板块手势冲突，改长按）
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            delete(s)
                                        } label: {
                                            Label("删除会话", systemImage: "trash")
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
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("好", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
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
            // 最新 → 最旧
            sessions = raw.compactMap { ChatSession.parse($0 as? [String: Any] ?? [:]) }
                .sorted { ($0.lastTime ?? 0) > ($1.lastTime ?? 0) }
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
                let j = try await auth.json("/api/sessions/merge", method: "POST", body: [
                    "sessions": [] as [Any],
                    "deleted": [s.id]
                ])
                // 校验服务器确实删除（401 透传/异常响应不含 ok:true → 视为未同步）
                if (j["ok"] as? Bool) != true {
                    rollbackDelete(s)
                }
            } catch {
                rollbackDelete(s)
            }
        }
    }

    /// 删除未同步到服务器：本地回滚 + 提示
    private func rollbackDelete(_ s: ChatSession) {
        if !sessions.contains(where: { $0.id == s.id }) {
            withAnimation {
                sessions.append(s)
                sessions.sort { ($0.lastTime ?? 0) > ($1.lastTime ?? 0) }
            }
        }
        deleteError = "删除未同步到服务器，请检查网络后重试"
    }
}

// MARK: - 机器人卡

struct BotCard: View {
    @Environment(AuthStore.self) private var auth
    @State private var online: Bool?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("轻聊 agent")
                    .font(.system(size: 15, weight: .semibold))
                Text("deepseek/deepseek-v4-flash")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(online == true ? Color.green : (online == false ? Color.red : Color.gray))
                    .frame(width: 6, height: 6)
                Text(online == true ? "在线" : (online == false ? "离线" : "检测中"))
                    .font(.system(size: 10))
                    .foregroundStyle(online == true ? Color.green : (online == false ? Color.red : Color.secondary))
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
        .task {
            // 真实连接状态
            let r = await auth.testConnection(server: auth.serverURL)
            online = r.hasPrefix("✅")
        }
    }
}

// MARK: - 会话行

struct SessionRow: View {
    let session: ChatSession
    var action: () -> Void = {}

    var body: some View {
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
        // 会话条目边框（深浅色通用细描边）
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        // 用 tap 手势而非 Button 包裹（Button 会与 swipeActions 滑动手势冲突，导致滑动删除失效）
        .onTapGesture { action() }
    }
}
