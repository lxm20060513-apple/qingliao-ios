import Foundation

// MARK: - v3.0 云端模式会话本地存储（文件 JSON，替代后端 /api/sessions/merge）
// 数据格式与后端 sessions.json 一致：{"sessions": [{"id","title","messages":[{role,content,timestamp}]}]}
// 存 App Documents/cloud_sessions.json，云端模式会话历史完全本地化

@MainActor
@Observable
final class CloudSessionStore {
    static let shared = CloudSessionStore()

    private(set) var sessions: [ChatSession] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("cloud_sessions.json")
    }

    init() {
        load()
    }

    /// 全量加载
    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["sessions"] as? [Any] else { return }
        sessions = arr.compactMap { ChatSession.parse($0 as? [String: Any] ?? [:]) }
        // 按最后时间倒序（新会话在前）
        sessions.sort { ($0.lastTime ?? 0) > ($1.lastTime ?? 0) }
    }

    /// 保存单个会话（upsert）
    func upsert(_ s: ChatSession) {
        if let idx = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[idx] = s
        } else {
            sessions.append(s)
        }
        persist()
    }

    /// 删除会话
    func delete(id: String) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    /// 重命名
    func rename(id: String, title: String) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = title
            persist()
        }
    }

    /// 从 ChatStore 保存当前会话（消息降级规则与后端一致：图片→[图片]，语音→[语音]）
    func saveChat(store: ChatStore) {
        guard !store.messages.isEmpty else { return }
        let msgs: [[String: Any]] = store.messages.map { m in
            var content = m.content
            if m.imageDataURL != nil {
                let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
                content = t.isEmpty ? "[图片]" : t + "\n[图片]"
            }
            if m.audioPath != nil {
                content = "[语音]"
            }
            var p: [String: Any] = ["role": m.role, "content": content]
            if let ts = m.timestamp { p["timestamp"] = ts }
            return p
        }
        let firstUserText = store.messages.first(where: { $0.isUser })?.content.prefix(30).description ?? ""
        let title = store.title.isEmpty ? firstUserText : store.title
        let payload = ChatSession(id: store.sessionId, title: title,
                                  messages: msgs.compactMap { ChatMessage.parse($0) })
        upsert(payload)
    }

    private func persist() {
        let arr: [[String: Any]] = sessions.map { s in
            [
                "id": s.id,
                "title": s.title,
                "messages": s.messages.map { m in
                    var p: [String: Any] = ["role": m.role, "content": m.content]
                    if let ts = m.timestamp { p["timestamp"] = ts }
                    return p
                }
            ]
        }
        let obj: [String: Any] = ["sessions": arr]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
