import Foundation
import Observation

// MARK: - 聊天会话状态：当前会话 id + 消息列表（UserDefaults 持久化当前会话）

@MainActor
@Observable
final class ChatStore {
    var sessionId: String
    var messages: [ChatMessage] = []
    var title = ""

    private let defaults = UserDefaults.standard
    private let sessionKey = "qingliao_current_session"

    init() {
        if let saved = defaults.string(forKey: sessionKey), !saved.isEmpty {
            sessionId = saved
        } else {
            sessionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(13).description
            defaults.set(sessionId, forKey: sessionKey)
        }
    }

    /// 切换会话（从会话列表点入）
    func load(_ s: ChatSession) {
        sessionId = s.id
        title = s.title
        messages = s.messages
        defaults.set(sessionId, forKey: sessionKey)
    }

    /// 新会话
    func newSession() {
        sessionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(13).description
        title = ""
        messages = []
        defaults.set(sessionId, forKey: sessionKey)
    }

    /// 追加本地消息（发送/流式开始）
    func append(_ m: ChatMessage) {
        messages.append(m)
        if title.isEmpty, m.isUser, !m.content.isEmpty {
            title = String(m.content.prefix(30))
        }
    }

    /// 流式结束后落库 assistant 消息（与最后一条相同则跳过，防重复）
    func upsertAssistant(_ text: String) {
        if let last = messages.last, last.role == "assistant", last.content == text {
            return
        }
        messages.append(ChatMessage(role: "assistant", content: text, timestamp: Date().timeIntervalSince1970 * 1000))
    }

    /// 发送请求用的历史消息（payload 形态）
    /// 只保留最后一条带图消息的 imageDataURL（前面已发过的图片不进 payload，防 base64 全量重复膨胀）
    func historyPayload() -> [[String: Any]] {
        var lastImgIdx: Int?
        for (i, m) in messages.enumerated() where m.imageDataURL != nil {
            lastImgIdx = i
        }
        return messages.enumerated().map { idx, m in
            var p = m.asPayload()
            if idx != lastImgIdx {
                p["content"] = m.content
            }
            return p
        }
    }

    /// 保存会话到后端（POST /api/sessions/merge）
    /// 图片消息降级为文本（不带 base64 data URL，防 sessions.json 膨胀；历史重放本就不渲染图片）
    func saveToServer(auth: AuthStore) async {
        guard !messages.isEmpty else { return }
        let msgs: [[String: Any]] = messages.map { m in
            var content = m.content
            if m.imageDataURL != nil {
                let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
                content = t.isEmpty ? "[图片]" : t + "\n[图片]"
            }
            var p: [String: Any] = ["role": m.role, "content": content]
            if let ts = m.timestamp { p["timestamp"] = ts }
            return p
        }
        let firstUserText = messages.first(where: { $0.isUser })?.content.prefix(30).description ?? ""
        let payload: [String: Any] = [
            "id": sessionId,
            "title": title.isEmpty ? firstUserText : title,
            "messages": msgs
        ]
        _ = try? await auth.request("/api/sessions/merge", method: "POST", body: [
            "sessions": [payload],
            "deleted": [] as [Any]
        ])
    }
}
