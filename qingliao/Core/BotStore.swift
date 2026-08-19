import Foundation
import Observation

// MARK: - Bot Store（v3.0.7 Bot Mode）：NAS bots.json 的 App 端缓存 + 选中状态
// 数据源唯一在后端（GET/POST/DELETE /api/bots，走 AuthStore 统一网络层带 token）
// 选中状态本地持久化（UserDefaults）；管理页/聊天选择器共用
//
// ⚠️ 性能（v3.0.7 fix）：@Observable 被聊天页/会话页环境观察，任何属性变化都会触发
// 两页 body 全量重算——因此 load 必须节流（非 force 5 分钟缓存），且 isLoading/errorText
// 只在真正发请求时翻转，避免 TabView 切页动画期间双页重算卡顿。

@MainActor
@Observable
final class BotStore {
    static let shared = BotStore()

    private(set) var bots: [QingliaoBot] = []
    var isLoading = false
    var errorText: String?

    /// 当前聊天选中的 bot id（nil = 通用助手）；UserDefaults 持久化跨启动
    var selectedBotID: String? {
        didSet {
            UserDefaults.standard.set(selectedBotID ?? "", forKey: selectedKey)
        }
    }

    private let selectedKey = "qingliao_selected_bot"

    /// id → bot O(1) 索引（bots 数组变化时同步；@Observable 观察 bots，索引只读不参与渲染）
    private var botIndex: [String: QingliaoBot] = [:]
    /// 上次成功加载时间（非 force 加载 5 分钟缓存，防止 tab 切换反复触发网络+状态翻转）
    private var lastLoadedAt: Date?

    init() {
        let saved = UserDefaults.standard.string(forKey: selectedKey) ?? ""
        if !saved.isEmpty { selectedBotID = saved }
    }

    // MARK: - 查询（O(1)）

    func bot(_ id: String?) -> QingliaoBot? {
        guard let id else { return nil }
        return botIndex[id]
    }

    var selectedBot: QingliaoBot? { bot(selectedBotID) }

    // MARK: - 网络 CRUD

    /// 拉取 bot 列表。force=true 强制重新请求并置加载态（管理页打开时用）；
    /// 默认 5 分钟缓存内直接返回（聊天/会话页 onAppear 调用，不惊扰 UI）。
    func load(auth: AuthStore, force: Bool = false) async {
        if !force, let last = lastLoadedAt, Date().timeIntervalSince(last) < 300 { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let j = try await auth.json("/api/bots")
            let arr = j["bots"] as? [[String: Any]] ?? []
            let newBots = arr.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return QingliaoBot(id: id,
                                   name: d["name"] as? String ?? "",
                                   systemPrompt: d["system_prompt"] as? String ?? "",
                                   model: d["model"] as? String ?? "",
                                   provider: d["provider"] as? String ?? "",
                                   avatar: d["avatar"] as? String ?? "")
            }
            // 内容无变化 → 不替换数组（@Observable 免触发重算）
            if newBots != bots {
                replaceBots(newBots)
            }
            // 选中项被外部删除（另一台设备）→ 回落通用助手
            if let sel = selectedBotID, bot(sel) == nil { selectedBotID = nil }
            errorText = nil
            lastLoadedAt = Date()
        } catch {
            errorText = "加载失败：\(error.localizedDescription)"
        }
    }

    /// 创建（id 为空）或更新（id 非空）
    @discardableResult
    func save(_ b: QingliaoBot, auth: AuthStore) async -> Bool {
        var body: [String: Any] = ["name": b.name,
                                   "system_prompt": b.systemPrompt,
                                   "model": b.model,
                                   "provider": b.provider,
                                   "avatar": b.avatar]
        if !b.id.isEmpty { body["id"] = b.id }
        do {
            let j = try await auth.json("/api/bots", method: "POST", body: ["bot": body])
            guard (j["ok"] as? Bool) == true else {
                errorText = "保存失败：服务器未确认"
                return false
            }
            let newID = (j["id"] as? String) ?? b.id
            let saved = QingliaoBot(id: newID, name: b.name, systemPrompt: b.systemPrompt,
                                    model: b.model, provider: b.provider, avatar: b.avatar)
            if let idx = bots.firstIndex(where: { $0.id == newID }) {
                var updated = bots
                updated[idx] = saved
                replaceBots(updated)
            } else {
                replaceBots(bots + [saved])
            }
            errorText = nil
            return true
        } catch {
            errorText = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func delete(id: String, auth: AuthStore) async -> Bool {
        do {
            let j = try await auth.json("/api/bots/\(id)", method: "DELETE")
            guard (j["ok"] as? Bool) == true else {
                errorText = "删除失败：服务器未确认"
                return false
            }
            replaceBots(bots.filter { $0.id != id })
            if selectedBotID == id { selectedBotID = nil }
            errorText = nil
            return true
        } catch {
            errorText = "删除失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 私有：数组 + 索引原子替换（防 @Observable 中间态）

    private func replaceBots(_ new: [QingliaoBot]) {
        bots = new
        var idx: [String: QingliaoBot] = [:]
        for b in new { idx[b.id] = b }
        botIndex = idx
    }
}