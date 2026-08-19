import Foundation
import Observation

// MARK: - Bot Store（v3.0.7 Bot Mode）：NAS bots.json 的 App 端缓存 + 选中状态
// 数据源唯一在后端（GET/POST/DELETE /api/bots，走 AuthStore 统一网络层带 token）
// 选中状态本地持久化（UserDefaults）；管理页/聊天选择器共用

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

    init() {
        let saved = UserDefaults.standard.string(forKey: selectedKey) ?? ""
        if !saved.isEmpty { selectedBotID = saved }
    }

    // MARK: - 查询

    func bot(_ id: String?) -> QingliaoBot? {
        guard let id else { return nil }
        return bots.first { $0.id == id }
    }

    var selectedBot: QingliaoBot? { bot(selectedBotID) }

    // MARK: - 网络 CRUD

    func load(auth: AuthStore) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let j = try await auth.json("/api/bots")
            let arr = j["bots"] as? [[String: Any]] ?? []
            bots = arr.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return QingliaoBot(id: id,
                                   name: d["name"] as? String ?? "",
                                   systemPrompt: d["system_prompt"] as? String ?? "",
                                   model: d["model"] as? String ?? "",
                                   provider: d["provider"] as? String ?? "",
                                   avatar: d["avatar"] as? String ?? "")
            }
            // 选中项被外部删除（另一台设备）→ 回落通用助手
            if let sel = selectedBotID, bot(sel) == nil { selectedBotID = nil }
            if bots.isEmpty { errorText = nil }
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
                bots[idx] = saved
            } else {
                bots.append(saved)
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
            bots.removeAll { $0.id == id }
            if selectedBotID == id { selectedBotID = nil }
            errorText = nil
            return true
        } catch {
            errorText = "删除失败：\(error.localizedDescription)"
            return false
        }
    }
}