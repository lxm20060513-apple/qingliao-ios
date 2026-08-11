import SwiftUI

// MARK: - 会话页（真实会话列表 + 滑动删除 + 点击进入聊天）

struct SessionsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat

    @State private var sessions: [ChatSession] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var scrollPos = ScrollPosition()
    @State private var deleteError: String?
    // v2.0.36：搜索 + 置顶
    @State private var searchText = ""
    @State private var searchResults: [[String: Any]] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var pinnedIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "qingliao_pinned_sessions") ?? [])
    var onOpenSession: (() -> Void)? = nil   // 切到聊天 tab

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "会话", trailing: AnyView(addButton))
            // v2.0.36：会话搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                TextField("搜索会话与消息", text: $searchText)
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onChange(of: searchText) { _, new in
                        searchTask?.cancel()
                        guard !new.trimmingCharacters(in: .whitespaces).isEmpty else {
                            searchResults = []
                            return
                        }
                        let q = new
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            guard !Task.isCancelled else { return }
                            await search(q)
                        }
                    }
                if isSearching {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
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
                        if isSearching {
                            // v2.0.36：搜索结果
                            if searching {
                                ProgressView().tint(.secondary).padding(.top, 30)
                            } else if searchResults.isEmpty {
                                Text("未找到相关内容")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 30)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(searchResults.enumerated()), id: \.offset) { _, r in
                                        SearchResultRow(result: r) {
                                            openSearchResult(r)
                                        }
                                    }
                                }
                            }
                        } else {
                            BotCard()
                            if sessions.isEmpty {
                                Text("暂无会话记录")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 30)
                            } else {
                                // 每条会话独立卡片 + 间隔（会话条目间距）
                                VStack(spacing: 8) {
                                    ForEach(sortedSessions) { s in
                                        SessionRow(session: s, pinned: pinnedIDs.contains(s.id)) {
                                            chat.load(s)
                                            onOpenSession?()
                                        }
                                        // 长按删除（滑动删除与 TabView 切板块手势冲突，改长按）
                                        .contextMenu {
                                            Button {
                                                togglePin(s)
                                            } label: {
                                                Label(pinnedIDs.contains(s.id) ? "取消置顶" : "置顶", systemImage: pinnedIDs.contains(s.id) ? "pin.slash" : "pin")
                                            }
                                            Button(role: .destructive) {
                                                delete(s)
                                            } label: {
                                                Label("删除会话", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 90)
                }
                .scrollPosition($scrollPos)
                .onChange(of: scrollPos.y) { _, y in
                    DockVisibility.shared.update(y ?? 0)
                }
                .refreshable {
                    if !isSearching { await load() }
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
            DockVisibility.shared.reset()   // 新建会话后 Dock 恢复显示
            onOpenSession?()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: - v2.0.36 搜索 / 置顶

    /// 置顶优先，其余按最新→最旧
    private var sortedSessions: [ChatSession] {
        sessions.sorted {
            let a = pinnedIDs.contains($0.id) ? 1 : 0
            let b = pinnedIDs.contains($1.id) ? 1 : 0
            if a != b { return a > b }
            return ($0.lastTime ?? 0) > ($1.lastTime ?? 0)
        }
    }

    private func togglePin(_ s: ChatSession) {
        if pinnedIDs.contains(s.id) {
            pinnedIDs.remove(s.id)
        } else {
            pinnedIDs.insert(s.id)
        }
        UserDefaults.standard.set(Array(pinnedIDs), forKey: "qingliao_pinned_sessions")
    }

    private func search(_ q: String) async {
        searching = true
        defer { searching = false }
        guard let j = try? await auth.json("/api/sessions/search", method: "POST", body: ["q": q]),
              let arr = j["results"] as? [[String: Any]] else {
            searchResults = []
            return
        }
        searchResults = arr
    }

    /// 搜索结果 → 打开对应会话（按 id 从完整列表找到并加载）
    private func openSearchResult(_ r: [String: Any]) {
        let sid = r["id"] as? String ?? ""
        if let s = sessions.first(where: { $0.id == sid }) {
            chat.load(s)
            searchText = ""
            searchResults = []
            onOpenSession?()
        }
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
        let deletingId = s.id
        withAnimation {
            sessions.removeAll { $0.id == deletingId }
        }
        if chat.sessionId == deletingId {
            chat.newSession()
        }
        Task {
            do {
                let j = try await auth.json("/api/sessions/merge", method: "POST", body: [
                    "sessions": [] as [Any],
                    "deleted": [s.id]
                ])
                let ok = (j["ok"] as? Bool) == true
                let deletedCount = (j["deleted"] as? Int) ?? -1
                if ok && deletedCount >= 0 {
                    // 服务器确认（deleted:1 删除成功 / deleted:0 服务器本无此会话）→ 刷新列表保持一致
                    await load()
                } else {
                    rollbackDelete(s)
                    deleteError = "删除未同步到服务器（服务器返回异常），请检查网络后重试"
                }
            } catch {
                rollbackDelete(s)
                deleteError = "删除未同步到服务器：\(error.localizedDescription)"
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

// MARK: - v2.0.36 搜索结果行（会话标题 + 命中片段）

struct SearchResultRow: View {
    let result: [String: Any]
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color.green.opacity(0.18), Color.teal.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.green.opacity(0.8))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(result["title"] as? String ?? "新对话")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let hits = result["hits"] as? [[String: Any]], let first = hits.first {
                    Text((first["snippet"] as? String) ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}

// MARK: - 会话行

struct SessionRow: View {
    let session: ChatSession
    var pinned: Bool = false
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
                HStack(spacing: 5) {
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.orange)
                    }
                    Text(session.title.isEmpty ? "新对话" : session.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
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
