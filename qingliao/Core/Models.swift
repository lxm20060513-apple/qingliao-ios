import Foundation

// MARK: - 聊天消息（content 可能是纯文本或数组，手动解析最稳）

struct ChatMessage: Identifiable {
    let role: String        // user / assistant / system
    let content: String     // 纯文本形态（数组 content 取 text 部分）
    let timestamp: TimeInterval?   // 毫秒

    var id: String { "\(role)-\(content.hashValue)-\(timestamp ?? 0)" }
    var isUser: Bool { role == "user" }

    /// 解析 messages 数组里的条目：content 可能是 String 或 [{type,text}...]
    static func parse(_ raw: Any) -> ChatMessage? {
        guard let d = raw as? [String: Any] else { return nil }
        let role = d["role"] as? String ?? ""
        let ts = d["timestamp"] as? TimeInterval
        var text = ""
        if let s = d["content"] as? String {
            text = s
        } else if let arr = d["content"] as? [[String: Any]] {
            // 多模态块：拼接 text 字段
            text = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if text.isEmpty {
                text = arr.contains { ($0["type"] as? String) == "image_url" } ? "[图片]" : ""
            }
        }
        return ChatMessage(role: role, content: text, timestamp: ts)
    }

    /// 本地新消息（无时间戳）
    static func local(role: String, content: String) -> ChatMessage {
        ChatMessage(role: role, content: content, timestamp: Date().timeIntervalSince1970 * 1000)
    }

    /// 请求体形态（发往 stream/start 的 messages）
    func asPayload() -> [String: Any] {
        var p: [String: Any] = ["role": role, "content": content]
        if let ts = timestamp { p["timestamp"] = ts }
        return p
    }
}

// MARK: - 会话（/api/sessions/list）

struct ChatSession: Identifiable {
    let id: String
    let title: String
    let messages: [ChatMessage]

    var lastMessageText: String { messages.last?.content ?? "" }
    var lastTime: TimeInterval? { messages.last?.timestamp }

    static func parse(_ d: [String: Any]) -> ChatSession? {
        guard let id = d["id"] as? String else { return nil }
        let title = d["title"] as? String ?? ""
        let msgs = (d["messages"] as? [Any] ?? []).compactMap { ChatMessage.parse($0) }
        return ChatSession(id: id, title: title, messages: msgs)
    }

    /// 列表页相对时间（分钟/小时/天）
    var relativeTime: String {
        guard let ts = lastTime else { return "" }
        let t = ts / 1000.0
        let diff = Date().timeIntervalSince1970 - t
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400)) 天" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: Date(timeIntervalSince1970: t))
    }
}

// MARK: - NAS 状态（/api/nas/status）

struct NASStatus {
    var hostname = ""
    var uptime = ""
    var cpu: Double = 0
    var memTotal: Double = 0
    var memUsed: Double = 0
    var mainDiskPct = 0.0
    var qingliaoAlive = false
    var qingliaoMem = 0.0
    var hermesAlive = false
    var hermesMem = 0.0

    static func parse(_ j: [String: Any]) -> NASStatus {
        var s = NASStatus()
        s.hostname = j["hostname"] as? String ?? ""
        s.uptime = j["uptime"] as? String ?? ""
        s.cpu = (j["cpu"] as? Double) ?? 0
        if let mem = j["mem"] as? [String: Any] {
            s.memTotal = (mem["total"] as? Double) ?? 0
            s.memUsed = (mem["used"] as? Double) ?? 0
        }
        // 主磁盘：volume1（最大数据盘）优先，否则 /overlay
        if let disks = j["disks"] as? [[String: Any]] {
            for d in disks {
                let mnt = d["mnt"] as? String ?? ""
                if mnt == "/volume1" || mnt.hasPrefix("/volume1") {
                    s.mainDiskPct = Double(d["pct"] as? String ?? "0") ?? 0
                    break
                }
            }
            if s.mainDiskPct == 0 {
                for d in disks {
                    if (d["mnt"] as? String) == "/overlay" {
                        s.mainDiskPct = Double(d["pct"] as? String ?? "0") ?? 0
                        break
                    }
                }
            }
        }
        if let svc = j["services"] as? [String: Any] {
            s.qingliaoAlive = (svc["qingliao"] as? Bool) ?? false
            s.qingliaoMem = (svc["qingliao_mem"] as? Double) ?? 0
            s.hermesAlive = (svc["hermes"] as? Bool) ?? false
            s.hermesMem = (svc["hermes_mem"] as? Double) ?? 0
        }
        return s
    }

    var memPct: Double { memTotal > 0 ? memUsed / memTotal : 0 }
    var memUsedText: String { byteText(memUsed) }
    var memTotalText: String { byteText(memTotal) }
    var qingliaoMemText: String { byteText(qingliaoMem) }
    var hermesMemText: String { byteText(hermesMem) }

    private func byteText(_ b: Double) -> String {
        if b >= 1_073_741_824 { return String(format: "%.1fG", b / 1_073_741_824) }
        if b >= 1_048_576 { return String(format: "%.0fM", b / 1_048_576) }
        return String(format: "%.0fK", b / 1024)
    }
}

// MARK: - HA 实体（/api/ha/states）

struct HAEntity {
    let entityID: String
    let state: String
    let friendlyName: String
    let attributes: [String: Any]

    static func parse(_ d: [String: Any]) -> HAEntity? {
        guard let eid = d["entity_id"] as? String else { return nil }
        let attrs = d["attributes"] as? [String: Any] ?? [:]
        let fn = attrs["friendly_name"] as? String ?? ""
        return HAEntity(entityID: eid, state: d["state"] as? String ?? "", friendlyName: fn, attributes: attrs)
    }
}
