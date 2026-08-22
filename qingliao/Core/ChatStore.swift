import Foundation
import Observation

// MARK: - 聊天会话状态：当前会话 id + 消息列表（UserDefaults 持久化当前会话）

@MainActor
@Observable
final class ChatStore {
    var sessionId: String
    var messages: [ChatMessage] = []
    var title = ""

    // v3.0.7 Bot Mode：当前会话关联的 bot id（nil = 通用助手）
    // bot 会话 id 用独立命名空间 "bot:<botId>:<sid>"，与普通会话完全隔离
    var botId: String? {
        didSet { defaults.set(botId ?? "", forKey: botKey) }
    }

    private let defaults = UserDefaults.standard
    // v3.0.1 fix：云端/本地会话 id 用不同 key 隔离（原共用一个 key → 切模式串 sessionId）
    // 注意：init 里不能访问 self.sessionKey（sessionId 未初始化会报 'self' used before init），
    // 因此 init 内直接判断 CloudConfig.shared（静态单例，不依赖 self）
    private var sessionKey: String {
        CloudConfig.shared.isCloudMode ? "qingliao_current_session_cloud" : "qingliao_current_session"
    }
    private let botKey = "qingliao_current_bot"

    init() {
        let key = CloudConfig.shared.isCloudMode ? "qingliao_current_session_cloud" : "qingliao_current_session"
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            sessionId = saved
        } else {
            sessionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(13).description
            defaults.set(sessionId, forKey: key)
        }
        let savedBot = defaults.string(forKey: botKey) ?? ""
        if !savedBot.isEmpty { botId = savedBot }
    }

    // MARK: - v3.0.7 Bot 会话命名空间

    /// 从会话 id 解析 bot id：普通会话 "<sid>" → nil；bot 会话 "bot:<botId>:<sid>" → botId
    static func botID(fromSessionID id: String) -> String? {
        let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "bot" else { return nil }
        return parts[1]
    }

    /// 生成新会话 id（当前是 bot 会话则带 bot 前缀命名空间）
    private func nextSessionID() -> String {
        let sid = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(13).description
        if let b = botId, !b.isEmpty { return "bot:\(b):\(sid)" }
        return sid
    }

    /// 切换聊天角色（nil = 通用助手）。保存当前会话由调用方负责（需 auth）；
    /// 这里只换会话：新 bot 会话用独立 id，不与其它 bot / 通用会话串数据
    func switchBot(id: String?) {
        guard botId != id else { return }
        botId = id
        sessionId = nextSessionID()
        title = ""
        messages = []
        highlightTarget = nil
        defaults.set(sessionId, forKey: sessionKey)
    }

    /// 切换会话（从会话列表点入）——v3.0.7：按 id 前缀恢复 bot 上下文
    func load(_ s: ChatSession) {
        sessionId = s.id
        botId = Self.botID(fromSessionID: s.id)
        title = s.title
        messages = s.messages
        defaults.set(sessionId, forKey: sessionKey)
    }

    /// v3.0.2 fix（会话串位根治）：模式切换时调用——清空当前模式的内存数据，
    /// 并按**新模式的 key** 重新读取当前会话 id。原实现：ChatStore 是全局单例，
    /// 切模式不复位 → 云端聊天时内存里还带本地 messages → 界面串位。
    /// v3.0.7：按新 key 的会话 id 前缀恢复 bot 上下文；云端模式不支持 bot（NAS 功能）→ 重置
    func switchToMode() {
        let key = CloudConfig.shared.isCloudMode ? "qingliao_current_session_cloud" : "qingliao_current_session"
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            sessionId = saved
            botId = Self.botID(fromSessionID: saved)
        } else {
            sessionId = nextSessionID()
            defaults.set(sessionId, forKey: key)
        }
        if CloudConfig.shared.isCloudMode { botId = nil }
        title = ""
        messages = []
        highlightTarget = nil
    }

    /// 新会话（v3.0.7：当前是 bot 会话则继续该 bot，生成带命名空间前缀的新 id）
    func newSession() {
        sessionId = nextSessionID()
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
    /// v2.0.102：去重仅限"连续两条 assistant 内容相同"（流式重复场景）——
    ///           上一条若是用户消息（新一轮提问），即使内容相同也必须新增（修复相同回复被吞）
    func upsertAssistant(_ text: String, agent: Bool = false) {
        if let idx = messages.indices.last, idx > 0,
           messages[idx].role == "assistant", messages[idx].content == text,
           messages[idx - 1].role == "assistant" {
            messages[idx].agent = agent || messages[idx].agent
            return
        }
        var m = ChatMessage(role: "assistant", content: text, timestamp: Date().timeIntervalSince1970 * 1000)
        m.agent = agent   // v2.0.96b：Agent 回复标记
        messages.append(m)
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
        // v3.0.10：图片保留条件（不降级为文本）
        // 云端模式：当前厂商 supportsVision
        // 本地模式：主模型支持视觉 OR 配置了视觉模型自动切换
        let visionOK: Bool = {
            if CloudConfig.shared.isCloudMode {
                return CloudConfig.shared.activeConfig?.supportsVision ?? false
            }
            // 本地模式：主模型支持视觉 → 直接 OK
            let mainModel = UserDefaults.standard.string(forKey: "qingliao_model") ?? ""
            if CloudConfig.modelSupportsVision(mainModel) { return true }
            // 主模型不支持 → 开关开 + 有视觉模型配置才保留图片，否则降级文本
            return CloudConfig.visionFallbackEnabled && CloudConfig.localVisionModel != nil
        }()
        return messages.map { m in
            var p = m.asPayload()
            if m.imageDataURL == nil {
                p["content"] = m.content
            } else if !visionOK {
                // 不支持视觉 → 图片降级为文本（内容 + [图片] 标记）
                let t = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                p["content"] = t.isEmpty ? "[图片]" : t + "\n[图片]"
            }
            return p
        }
    }

    /// 保存会话（v3.0.1：按模式分流——云端写本地 CloudSessionStore 文件，本地走后端）
    /// 本地模式：POST /api/sessions/merge（2.0 原逻辑）
    /// 云端模式：写 App 本地文档（防云端会话串进本地 AI 后端 sessions）
    /// 图片消息降级为文本（不带 base64 data URL，防 sessions.json 膨胀；历史重放本就不渲染图片）
    func saveToServer(auth: AuthStore) async {
        await saveToServer(auth: auth, sessionId: sessionId, messages: messages, title: title)
    }

    /// v3.0.7 参数化快照版：切换角色（switchBot）前调用——切换会清空 messages，
    /// 异步保存若不捕获快照会读到空数组丢会话。消息降级规则与 saveToServer 一致。
    func saveToServer(auth: AuthStore, sessionId sid: String, messages msgs: [ChatMessage], title t: String) async {
        guard !msgs.isEmpty else { return }
        // v3.0.1 fix：云端模式会话存本地文件，绝不写后端（否则串到本地 AI）
        if CloudConfig.shared.isCloudMode {
            CloudSessionStore.shared.saveChat(sessionId: sid, messages: msgs, title: t)
            return
        }
        let msgsPayload: [[String: Any]] = msgs.map { m in
            var content = m.content
            if m.imageDataURL != nil {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                content = trimmed.isEmpty ? "[图片]" : trimmed + "\n[图片]"
            }
            if m.audioPath != nil {   // v2.0.61：语音消息降级为文本（文件在本地，不同步服务器）
                content = "[语音]"
            }
            var p: [String: Any] = ["role": m.role, "content": content]
            if let ts = m.timestamp { p["timestamp"] = ts }
            return p
        }
        let firstUserText = msgs.first(where: { $0.isUser })?.content.prefix(30).description ?? ""
        let payload: [String: Any] = [
            "id": sid,
            "title": t.isEmpty ? firstUserText : t,
            "messages": msgsPayload
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

    /// v3.0.22：导出为 Markdown 格式（保留结构化排版）
    func exportMarkdown() -> String {
        var lines: [String] = []
        lines.append("# " + (title.isEmpty ? "未命名会话" : title))
        lines.append("")
        for m in messages {
            let who = m.isUser ? "**我**" : "**AI**"
            let t = m.timestamp.map { ts -> String in
                let d = Date(timeIntervalSince1970: ts / 1000)
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                return f.string(from: d)
            } ?? ""
            var content = m.content
            if m.imageDataURL != nil {
                let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
                content = c.isEmpty ? "![图片]" : c + "\n![图片]"
            }
            lines.append("### \(who) · \(t)")
            lines.append("")
            lines.append(content)
            lines.append("")
            lines.append("---")
            lines.append("")
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

    // MARK: - v3.0.27 图片持久化

    /// 上传图片到服务器，返回可访问的 URL
    func uploadImage(_ imageData: Data, auth: AuthStore) async -> String? {
        guard let config = CloudConfig.shared.activeConfig else { return nil }
        var base = config.baseURL
        if !base.hasPrefix("http") { base = "https://" + base }
        guard let url = URL(string: base + "/api/files/upload") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(auth.token, forHTTPHeaderField: "X-Auth-Token")

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileURL = json["url"] as? String else { return nil }
        // v3.0.37：后端返回相对路径 → 拼 baseURL 成完整可访问 URL（WiFi 直连 / 蜂窝中继均按各自 base）
        if fileURL.hasPrefix("/") {
            let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
            return trimmedBase + fileURL
        }
        return fileURL
    }
}
