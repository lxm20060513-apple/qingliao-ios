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
    private weak var stream: StreamClient?
    var lastError: String?
    var lastInjectedCount = 0

    /// 已注入的消息 id（本地防重复——App 前后台频繁轮询，done 标记有网络延迟）
    /// v3.0.84fix：持久化到 UserDefaults（原纯内存 Set，App 重启丢 → 未 markDone 的推送会重复注入+重复通知）
    private var consumedIds: Set<String>
    private var pollingTask: Task<Void, Never>?
    private let consumedKey = "qingliao_inbox_consumed_ids"

    /// 推送轮询间隔（秒）。App 前台持续轮询；后台系统会冻结 task。
    var pollInterval: Double = 5

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
    func attach(auth: AuthStore, chat: ChatStore, stream: StreamClient? = nil) {
        self.auth = auth
        self.chat = chat
        self.stream = stream
    }

    // MARK: - 消费消息（注入当前会话 + 通知 + 标已读）

    /// 拉一次收件箱，把新消息注入当前聊天会话。
    func pollOnce() async {
        guard let auth, let chat else { return }
        do {
            let items = try await inboxItems(auth)
            lastInjectedCount = 0
            guard !items.isEmpty else { return }
            // v3.0.90 fix：流式进行中不注入。后端 AI 回复 done 即推收件箱（_maybe_push_app），
            // 而流式回复要等 done → finish → upsertAssistant 才落库到 chat.messages；若本轮
            // 轮询抢在落库前拉到推送，shouldSkipDuplicate 遍历不到这条回复 → 误判不重复 →
            // 重复注入（AI 回答气泡 + 🔔推送气泡同内容）。流式中跳过本轮（不 markDone），
            // 流结束 15s 后下一轮再比对，此时回复已落库，去重必然命中。
            if let s = stream, s.isStreaming { return }
            for it in items {
                let id = it.id
                guard !consumedIds.contains(id) else { continue }
                consume(id)
                // v3.0.87 fix：去重——AI 回复完成自动推(_maybe_push_app)的摘要与该会话流式渲染的回复重复。
                // 当前会话最后一条 assistant(非推送) 文本已包含此推送正文 → 判定为同一条回复，不再重复注入（仅标记已读），
                // 避免用户看到「流式回复 + 🔔推送」两条相同内容。
                if shouldSkipDuplicate(push: it.text, in: chat.messages) {
                    await markDone(id, auth: auth)
                    continue
                }
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

    /// v3.0.88 fix：收件箱推送 vs 会话内流式回复去重（v3.0.87 版因空白格式不匹配失效）。
    /// 后端 _maybe_push_app 用 re.sub(r"\s+"," ",...) 把回复压成单行摘要，而流式回复 content 保留换行/段落，
    /// 直接 contains 会匹配失败 → 重复注入。改为双方先压缩空白再双向比对 + 截断前缀兜底。
    private func shouldSkipDuplicate(push text: String, in messages: [ChatMessage]) -> Bool {
        let core = normalizeWhitespace(text).replacingOccurrences(of: "…", with: "")
        guard !core.isEmpty else { return false }
        for m in messages.reversed() {
            guard m.role == "assistant" && !m.isPush else { continue }
            let cm = normalizeWhitespace(m.content)
            // 双向包含：完整回复包含推送摘要（长回复被截断）或推送摘要包含完整回复
            if cm.contains(core) || core.contains(cm) { return true }
            // 截断前缀兜底：推送是完整回复的截断（前 N 字）摘要，且摘要足够长避免短文本误判
            if core.count >= 10, cm.hasPrefix(core) { return true }
        }
        return false
    }

    /// 压缩全部空白（换行/多空格 → 单空格），使推送摘要（已压单行）与流式回复（带换行）可比对
    private func normalizeWhitespace(_ s: String) -> String {
        return s.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .split(separator: " ").joined(separator: " ")
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
