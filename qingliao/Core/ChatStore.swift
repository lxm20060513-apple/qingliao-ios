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
        highlightTarget = nil   // v2.0.44：新建会话清除残留定位目标
        defaults.set(sessionId, forKey: sessionKey)
    }

    // MARK: - v2.0.58 两步走新建会话
    // MARK: - v2.0.65 未读红点（本地概念：会话有新消息且未打开）

    var unread: [String: Bool] = [:]              // sessionId -> 有未读
    private var seenTimes: [String: TimeInterval] = [:]   // 各会话上次查看时间

    /// 列表加载后同步未读（有 lastTime 且晚于上次查看 → 标未读）
    func syncUnread(from sessions: [ChatSession], currentId: String) {
        for s in sessions {
            guard s.id != currentId, let lt = s.lastTime else { continue }
            if lt > (seenTimes[s.id] ?? 0) + 1000 {
                unread[s.id] = true
            }
        }
    }

    func markRead(_ id: String) {
        unread[id] = nil
        seenTimes[id] = Date().timeIntervalSince1970 * 1000
    }

    var totalUnread: Int { unread.count }

    /// 请求新建会话（只设标志不清数据）：ChatView 观察到后先切欢迎页卸载列表，
    /// 下一帧再 newSession——v2.0.44 的"先切tab再清空"在 tab 切换动画期间（半隐藏状态）
    /// 清空仍崩（用户实测 v2.0.57 新建/删除都闪退）；两步走是清空按钮验证过的稳定模式
    var pendingNewSession = false

    func requestNewSession() {
        pendingNewSession = true
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

    /// v2.0.59：按 id 标记消息发送失败（显示重试按钮）
    func markFailed(id: String) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].failed = true
        }
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
            if m.audioPath != nil {   // v2.0.61：语音消息降级为文本（文件在本地，不同步服务器）
                content = "[语音]"
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

    // MARK: - v2.0.36

    /// 导出当前会话为纯文本（用户/AI 消息 + 时间）
    func exportText() -> String {
        var lines: [String] = []
        lines.append("轻聊会话导出 · " + (title.isEmpty ? "未命名会话" : title))
        lines.append("===================================")
        for m in messages {
            let who = m.isUser ? "我" : "AI"
            let t = m.timestamp.map { ts -> String in
                let d = Date(timeIntervalSince1970: ts / 1000)
                let f = DateFormatter()
                f.dateFormat = "MM-dd HH:mm"
                return f.string(from: d)
            } ?? ""
            var content = m.content
            if m.imageDataURL != nil {
                let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
                content = c.isEmpty ? "[图片]" : c + "\n[图片]"
            }
            lines.append("\n[\(who) \(t)]")
            lines.append(content)
        }
        return lines.joined(separator: "\n")
    }

    /// 清空当前会话消息（保留会话 id 与标题）
    func clearMessages() {
        messages = []
    }

    // MARK: - v2.0.43 上下文管理 / 搜索定位

    /// 搜索定位目标（从会话列表点搜索结果时设置，ChatView 滚动+高亮）
    var highlightTarget: (role: String, content: String)?

    /// 上下文估算（近似 token = 字符数/4 + 消息数基础开销）
    var contextInfo: (tokens: Int, count: Int) {
        let chars = messages.reduce(0) { $0 + $1.content.count }
        return (chars / 4 + messages.count * 3, messages.count)
    }

    /// 压缩上下文：保留最近 20 条，更早的消息替换为一条占位标记
    /// （本地压缩不调 AI 摘要，立省 token；需要摘要可让 AI 从占位标记处续聊）
    func compressContext(keepLast: Int = 20) -> Bool {
        guard messages.count > keepLast + 1 else { return false }
        let dropped = messages.count - keepLast
        let firstUser = messages.first { $0.isUser }?.content.prefix(30).description ?? ""
        let marker = ChatMessage(role: "system", content: "（已压缩上下文：早期对话共 \(dropped) 条已省略，首条主题：\(firstUser)）",
                                 timestamp: messages.first?.timestamp)
        messages.removeFirst(dropped)
        messages.insert(marker, at: 0)
        return true
    }

    /// 按角色+内容前缀查找消息索引（搜索定位用，内容太长时前缀匹配）
    func indexOfMessage(role: String, contentPrefix: String) -> Int? {
        let prefix = String(contentPrefix.prefix(60))
        return messages.firstIndex {
            $0.role == role && $0.content.hasPrefix(prefix)
        }
    }
}
