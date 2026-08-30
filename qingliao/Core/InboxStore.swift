import Foundation
import Observation

/// v3.0.82：Hermes 主动推送给轻聊App 的收件箱（本地轮询版）。
///
/// 背景：App 是「App 主动请求 → 服务端响应」模型，服务端没法主动往 App 塞消息。
/// 本 Store 轮询后端 /api/inbox（Hermes 主动推的消息队列），拉到就：
///   1. 注入当前聊天会话（assistant 角色，isPush 标记 → 气泡显示「🔔 推送」标签）
///   2. 弹本地通知（侧载 App 无 APNs，只能本地通知）
///   3. 标记已读（POST /api/inbox/{id}/done），防重复显示
///
/// 方案B 取舍：消息直接进当前聊天会话（改动小），代价是会随会话历史一起进
/// 模型上下文（下轮发消息全带进去）——用户已确认接受此取舍。
@MainActor
@Observable
final class InboxStore {
    static let shared = InboxStore()

    private var auth: AuthStore?
    private weak var chat: ChatStore?
    var lastError: String?
    var lastInjectedCount = 0

    /// 已注入的消息 id（本地防重复——App 前后台频繁轮询，done 标记有网络延迟）
    /// v3.0.84fix：持久化到 UserDefaults（原纯内存 Set，App 重启丢 → 未 markDone 的推送会重复注入+重复通知）
    private var consumedIds: Set<String>
    private var pollingTask: Task<Void, Never>?
    private let consumedKey = "qingliao_inbox_consumed_ids"

    private init() {
        consumedIds = Set(UserDefaults.standard.stringArray(forKey: "qingliao_inbox_consumed_ids") ?? [])
    }

    private func consume(_ id: String) {
        consumedIds.insert(id)
        // 只保留最近 200 个去重 id（防无限增长；远大于队列上限 100）
        if consumedIds.count > 200 {
            let dropped = consumedIds.sorted().dropFirst(consumedIds.count - 200)
            consumedIds.subtract(dropped)
        }
        UserDefaults.standard.set(Array(consumedIds), forKey: consumedKey)
    }

    /// 注入依赖（QingliaoApp .task 调用，与 PinStore.shared.attach 一致）
    func attach(auth: AuthStore, chat: ChatStore) {
        self.auth = auth
        self.chat = chat
    }

    // MARK: - 消费消息（注入当前会话 + 通知 + 标已读）

    /// 拉一次收件箱，把新消息注入当前聊天会话。
    func pollOnce() async {
        guard let auth, let chat else { return }
        do {
            let items = try await inboxItems(auth)
            lastInjectedCount = 0
            guard !items.isEmpty else { return }
            for it in items {
                let id = it.id
                guard !consumedIds.contains(id) else { continue }
                consume(id)
                // 注入当前会话（assistant 角色 + 推送标记）
                var msg = ChatMessage(role: "assistant", content: it.text,
                                      timestamp: Date().timeIntervalSince1970 * 1000)
                msg.isPush = true
                chat.append(msg)
                lastInjectedCount += 1
                // 弹本地通知（侧载无 APNs，用本地通知横幅兜底；App 前台也弹）
                NotificationHelper.notify(title: "轻聊 · 推送", body: it.text, sessionId: chat.sessionId)
                // 标记已读（防重复；失败不阻塞，下轮靠 consumedIds 去重）
                await markDone(id, auth: auth)
            }
            // 注入后保存会话，让推送消息也落库（用户切会话/重开还能看到）
            await chat.saveToServer(auth: auth)
        } catch {
            lastError = "\(error)"
        }
    }

    // MARK: - 轮询启动/停止

    /// 启动后台轮询（App 前台持续拉）。防重复启动。
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.pollOnce()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 前台恢复：重启轮询任务（旧任务可能已被系统冻结）
    func refreshOnActive() {
        // 若轮询任务已停止（后台冻结），重启；若还在则不需重复启（startPolling 幂等）
        if pollingTask == nil { startPolling() }
        // 立即拉一次，不等下一轮
        Task { await self.pollOnce() }
    }

    // MARK: - 后端 API

    private func inboxItems(_ auth: AuthStore) async throws -> [(id: String, text: String)] {
        let json = try await auth.json("/api/inbox", method: "GET")
        guard let arr = json["items"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String, let text = d["text"] as? String else { return nil }
            return (id, text)
        }
    }

    private func markDone(_ id: String, auth: AuthStore) async {
        _ = try? await auth.request("/api/inbox/\(id)/done", method: "POST", body: [:])
    }
}
