import Foundation
import SwiftUI

// MARK: - Bot Mode（v3.0.7：每个 Bot 独立人设/模型，独立会话；数据源 NAS bots.json）
// v3.0.7 beautify：内置淡雅 SF Symbols 头像预设（存 "sfs:<symbol>" 前缀，兼容既有 emoji）

/// 内置 Bot 头像预设（轻量扁平、低饱和淡雅色，符合 iOS 审美）
/// id = 存储值（sfs: 前缀），symbol = SF Symbol 名，color = 图标着色
struct BotIconPreset: Identifiable {
    let id: String        // 如 "sfs:sparkles"
    let symbol: String    // "sparkles"
    let color: Color
}

/// Bot Mode：每个 Bot 独立人设/模型，独立会话；数据源 NAS bots.json
struct QingliaoBot: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var systemPrompt: String
    var model: String
    var provider: String
    var avatar: String

    enum CodingKeys: String, CodingKey {
        case id, name, model, provider, avatar
        case systemPrompt = "system_prompt"
    }

    /// 模型副标题（模型名 + 供应商；为空则显示"默认模型"）
    var displayModel: String {
        if !model.isEmpty { return provider.isEmpty ? model : "\(model) · \(provider)" }
        return provider.isEmpty ? "默认模型" : provider
    }

    /// 头像显示（emoji / 单字 / 默认图标）
    var avatarText: String {
        let a = avatar.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return "🤖" }
        // emoji 可能多字符（如 🐱），第一个字簇即可
        return String(a.prefix(2))
    }
}

extension QingliaoBot {
    /// 内置头像预设（精选 24 个淡雅符号）
    static let iconPresets: [BotIconPreset] = [
        BotIconPreset(id: "sfs:sparkles",          symbol: "sparkles",                    color: Color(red: 0.55, green: 0.5, blue: 0.9)),
        BotIconPreset(id: "sfs:wand.and.stars",    symbol: "wand.and.stars",              color: Color(red: 0.6, green: 0.45, blue: 0.85)),
        BotIconPreset(id: "sfs:leaf.fill",         symbol: "leaf.fill",                   color: Color(red: 0.35, green: 0.6, blue: 0.45)),
        BotIconPreset(id: "sfs:heart.fill",        symbol: "heart.fill",                  color: Color(red: 0.9, green: 0.55, blue: 0.6)),
        BotIconPreset(id: "sfs:star.fill",         symbol: "star.fill",                   color: Color(red: 0.95, green: 0.75, blue: 0.35)),
        BotIconPreset(id: "sfs:moon.stars.fill",   symbol: "moon.stars.fill",             color: Color(red: 0.5, green: 0.55, blue: 0.8)),
        BotIconPreset(id: "sfs:sun.max.fill",      symbol: "sun.max.fill",                color: Color(red: 0.95, green: 0.7, blue: 0.3)),
        BotIconPreset(id: "sfs:cloud.sun.fill",    symbol: "cloud.sun.fill",              color: Color(red: 0.55, green: 0.7, blue: 0.8)),
        BotIconPreset(id: "sfs:flame.fill",        symbol: "flame.fill",                  color: Color(red: 0.9, green: 0.6, blue: 0.35)),
        BotIconPreset(id: "sfs:drop.fill",         symbol: "drop.fill",                   color: Color(red: 0.4, green: 0.6, blue: 0.9)),
        BotIconPreset(id: "sfs:snowflake",         symbol: "snowflake",                   color: Color(red: 0.5, green: 0.75, blue: 0.85)),
        BotIconPreset(id: "sfs:bolt.fill",         symbol: "bolt.fill",                   color: Color(red: 0.9, green: 0.75, blue: 0.3)),
        BotIconPreset(id: "sfs:book.fill",         symbol: "book.fill",                   color: Color(red: 0.75, green: 0.55, blue: 0.35)),
        BotIconPreset(id: "sfs:paintpalette.fill", symbol: "paintpalette.fill",           color: Color(red: 0.85, green: 0.5, blue: 0.6)),
        BotIconPreset(id: "sfs:camera.fill",       symbol: "camera.fill",                 color: Color(red: 0.5, green: 0.55, blue: 0.65)),
        BotIconPreset(id: "sfs:music.note",        symbol: "music.note",                  color: Color(red: 0.8, green: 0.5, blue: 0.7)),
        BotIconPreset(id: "sfs:mic.fill",          symbol: "mic.fill",                    color: Color(red: 0.6, green: 0.5, blue: 0.8)),
        BotIconPreset(id: "sfs:cpu.fill",          symbol: "cpu.fill",                    color: Color(red: 0.45, green: 0.6, blue: 0.75)),
        BotIconPreset(id: "sfs:chip.fill",         symbol: "chip.fill",                   color: Color(red: 0.4, green: 0.65, blue: 0.55)),
        BotIconPreset(id: "sfs:car.fill",          symbol: "car.fill",                    color: Color(red: 0.55, green: 0.6, blue: 0.75)),
        BotIconPreset(id: "sfs:airplane",          symbol: "airplane",                    color: Color(red: 0.55, green: 0.65, blue: 0.8)),
        BotIconPreset(id: "sfs:rocket.fill",       symbol: "rocket.fill",                 color: Color(red: 0.7, green: 0.5, blue: 0.85)),
        BotIconPreset(id: "sfs:telescope.fill",    symbol: "telescope.fill",              color: Color(red: 0.45, green: 0.55, blue: 0.7)),
        BotIconPreset(id: "sfs:pawprint.fill",     symbol: "pawprint.fill",               color: Color(red: 0.85, green: 0.65, blue: 0.45)),
    ]
}

extension QingliaoBot {
    /// 是否为内置 SF Symbol 头像（sfs: 前缀）
    var isSFSymbolAvatar: Bool { avatar.hasPrefix("sfs:") }
    /// 内置头像的 symbol 名（sfs: 前缀剥离）
    var avatarSymbol: String {
        isSFSymbolAvatar ? String(avatar.dropFirst("sfs:".count)) : ""
    }
    /// 内置头像的着色（未命中预设回退墨蓝色）
    var avatarColor: Color {
        guard let p = Self.iconPresets.first(where: { $0.id == avatar }) else {
            return Color(red: 0.5, green: 0.55, blue: 0.8)
        }
        return p.color
    }
    /// 通用头像渲染（内置符号 → Image；否则 emoji Text）——三处统一用，防样式漂移
    @ViewBuilder
    func avatarIcon(size: CGFloat) -> some View {
        if isSFSymbolAvatar, !avatarSymbol.isEmpty {
            Image(systemName: avatarSymbol)
                .font(.system(size: size))
                .foregroundStyle(avatarColor)
        } else {
            Text(avatarText)
                .font(.system(size: size))
        }
    }
}

// MARK: - 聊天消息（content 可能是纯文本或数组，手动解析最稳）

struct ChatMessage: Identifiable {
    let role: String        // user / assistant / system
    let content: String     // 纯文本形态（数组 content 取 text 部分）
    let timestamp: TimeInterval?   // 毫秒
    var imageDataURL: String?      // data:image/jpeg;base64,...（本地发送的图片）
    var failed: Bool = false       // v2.0.59：发送失败标记（显示重试按钮）
    var audioPath: String?         // v2.0.61：本地语音消息文件路径（m4a）
    var queued: Bool = false       // v2.0.88：AI 回答中发送，排队等待自动处理
    var withdrawn: Bool = false    // v2.0.92：已撤回（显示"[已撤回]"占位）
    var agent: Bool = false        // v2.0.96b：Agent 回复标记（工具调用回复，显示标签）
    var voiceCommand: Bool = false   // v3.0.19：语音指令触发（长按智能球，显示 🎤 标记）

    var id: String { "\(role)-\(content.hashValue)-\(imageDataURL?.hashValue ?? 0)-\(timestamp ?? 0)" }
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
            // 多模态块：拼接 text 字段，图片记为 [图片]（历史消息不带 data URL，防超大 JSON）
            text = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let hasImage = arr.contains { ($0["type"] as? String) == "image_url" }
            if hasImage {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                text = t.isEmpty ? "[图片]" : t + "\n[图片]"
            }
        }
        return ChatMessage(role: role, content: text, timestamp: ts)
    }

    /// 本地新消息（无时间戳）
    static func local(role: String, content: String, imageDataURL: String? = nil) -> ChatMessage {
        ChatMessage(role: role, content: content, timestamp: Date().timeIntervalSince1970 * 1000,
                    imageDataURL: imageDataURL)
    }

    /// 请求体形态（发往 stream/start 的 messages）：带图时用 content 数组
    func asPayload() -> [String: Any] {
        var p: [String: Any] = ["role": role]
        if let img = imageDataURL {
            var blocks: [[String: Any]] = []
            if !content.isEmpty {
                blocks.append(["type": "text", "text": content])
            }
            blocks.append(["type": "image_url", "image_url": ["url": img]])
            p["content"] = blocks
        } else {
            p["content"] = content
        }
        if let ts = timestamp { p["timestamp"] = ts }
        return p
    }
}

// MARK: - 会话（/api/sessions/list）

struct ChatSession: Identifiable {
    let id: String
    var title: String   // v2.0.43 重命名（SessionsView 本地改）
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

// MARK: - 模型使用量（/api/nas/providers-usage，v3.0.36）

/// v3.0.36：看板「模型使用量」栏数据
/// 三种形态：payg 余额（DeepSeek/StepFun total/granted/topped_up）、
/// plan 百分比配额（OpenCode rolling/weekly/monthly percent）、unsupported（无公开接口）
struct ProviderUsage: Identifiable {
    let provider: String
    let name: String
    let mode: String          // payg=按量余额 / plan=订阅配额
    let available: Bool
    let unsupported: Bool     // 官方无公开用量接口
    let total: Double
    let granted: Double
    let toppedUp: Double
    let currency: String
    let error: String
    // plan 百分比配额（opencode /zen/go/v1/usage）
    let usagePercent: [String: Double]   // rolling/weekly/monthly → percent
    let usageReset: [String: String]     // rolling/weekly/monthly → resetsAt ISO

    var id: String { provider }

    /// 主文本：余额（payg）或当前用量百分比（plan）
    var balanceText: String {
        if unsupported { return "控制台查看" }
        if mode == "plan", let monthly = usagePercent["monthly"] {
            return String(format: "月用量 %.0f%%", monthly)
        }
        if total > 0 {
            let sym = currency == "USD" ? "$" : "¥"
            return String(format: "%@%.2f", sym, total)
        }
        return "—"
    }

    /// 副文本：plan → 周/滚动百分比；payg → 充值/赠金明细
    var detailText: String {
        if unsupported { return error.isEmpty ? "无公开接口" : error }
        if !available { return error.isEmpty ? "不可用" : error }
        if mode == "plan" {
            var parts: [String] = []
            if let w = usagePercent["weekly"] { parts.append(String(format: "周 %.0f%%", w)) }
            if let r = usagePercent["rolling"] { parts.append(String(format: "滚动 %.0f%%", r)) }
            return parts.isEmpty ? "订阅中" : parts.joined(separator: " · ")
        }
        var parts: [String] = []
        if toppedUp > 0 { parts.append(String(format: "充值 %.2f", toppedUp)) }
        if granted > 0 { parts.append(String(format: "赠金 %.2f", granted)) }
        return parts.isEmpty ? "可用" : parts.joined(separator: " · ")
    }

    static func parse(_ d: [String: Any]) -> ProviderUsage {
        let b = d["balance"] as? [String: Any] ?? [:]
        var pct: [String: Double] = [:]
        var reset: [String: String] = [:]
        if let u = d["usage"] as? [String: Any] {
            for k in ["rolling", "weekly", "monthly"] {
                if let v = u[k] as? [String: Any] {
                    if let p = v["percent"] as? Double { pct[k] = p }
                    else if let p = v["percent"] as? String { pct[k] = Double(p) ?? 0 }
                    if let r = v["resetsAt"] as? String { reset[k] = r }
                }
            }
        }
        return ProviderUsage(
            provider: d["provider"] as? String ?? "",
            name: d["name"] as? String ?? d["provider"] as? String ?? "",
            mode: d["mode"] as? String ?? "payg",
            available: (d["available"] as? Bool) ?? false,
            unsupported: (d["unsupported"] as? Bool) ?? false,
            total: (b["total"] as? Double) ?? 0,
            granted: (b["granted"] as? Double) ?? 0,
            toppedUp: (b["topped_up"] as? Double) ?? 0,
            currency: b["currency"] as? String ?? "CNY",
            error: d["error"] as? String ?? "",
            usagePercent: pct,
            usageReset: reset
        )
    }
}

// MARK: - NAS 状态（/api/nas/status）

struct NASStatus {
    var hostname = ""
    var uptime = ""
    var cpu: Double = 0
    var memTotal: Double = 0
    var memUsed: Double = 0
    var disks: [NASDisk] = []
    var qingliaoAlive = false
    var qingliaoMem = 0.0
    var hermesAlive = false
    var hermesMem = 0.0
    var hermesVersion = ""   // v3.0.8：Hermes 容器版本（docker exec 实时读）

    /// 最大磁盘使用率（PWA 概览语义）
    var maxDiskPct: Double {
        disks.map(\.pct).max() ?? 0
    }

    static func parse(_ j: [String: Any]) -> NASStatus {
        var s = NASStatus()
        s.hostname = j["hostname"] as? String ?? ""
        s.uptime = j["uptime"] as? String ?? ""
        s.cpu = (j["cpu"] as? Double) ?? 0
        if let mem = j["mem"] as? [String: Any] {
            s.memTotal = (mem["total"] as? Double) ?? 0
            s.memUsed = (mem["used"] as? Double) ?? 0
        }
        if let disks = j["disks"] as? [[String: Any]] {
            s.disks = disks.compactMap { NASDisk.parse($0) }
        }
        if let svc = j["services"] as? [String: Any] {
            s.qingliaoAlive = (svc["qingliao"] as? Bool) ?? false
            s.qingliaoMem = (svc["qingliao_mem"] as? Double) ?? 0
            s.hermesAlive = (svc["hermes"] as? Bool) ?? false
            s.hermesMem = (svc["hermes_mem"] as? Double) ?? 0
            s.hermesVersion = (svc["hermes_version"] as? String) ?? ""
        }
        return s
    }

    var memPct: Double { memTotal > 0 ? memUsed / memTotal : 0 }
    var memUsedText: String { byteText(memUsed) }
    var memTotalText: String { byteText(memTotal) }
    var qingliaoMemText: String { byteText(qingliaoMem) }
    var hermesMemText: String { byteText(hermesMem) }
    var cpuText: String { String(format: "%.1f%%", cpu) }
    var maxDiskPctText: String { String(format: "%.0f%%", maxDiskPct) }
    /// v3.0.22：硬件温度预格式化（DashboardView hwDetail 内联格式化搬到模型层）
    var hwCpuText: String { "" }
    var hwSsdText: String { "" }

    private func byteText(_ b: Double) -> String {
        if b >= 1_073_741_824 { return String(format: "%.1fG", b / 1_073_741_824) }
        if b >= 1_048_576 { return String(format: "%.0fM", b / 1_048_576) }
        return String(format: "%.0fK", b / 1024)
    }
}

// MARK: - NAS 磁盘

struct NASDisk: Identifiable {
    let mnt: String
    let fs: String
    let used: Double
    let total: Double
    let pct: Double
    let kind: String  // v3.0.36：system=系统盘分区 / data=数据卷（/volume*）

    var id: String { mnt }
    var isSystem: Bool { kind == "system" }
    var usedText: String { byteText(used) }
    var totalText: String { byteText(total) }
    var pctText: String { String(format: "%.0f%%", pct) }

    static func parse(_ d: [String: Any]) -> NASDisk? {
        guard let mnt = d["mnt"] as? String else { return nil }
        let fs = d["fs"] as? String ?? ""
        let used = (d["used"] as? Double) ?? 0
        let total = (d["total"] as? Double) ?? 0
        let pct = Double(d["pct"] as? String ?? "0") ?? 0
        let kind = d["kind"] as? String ?? (mnt.hasPrefix("/volume") || mnt.hasPrefix("/data") ? "data" : "system")
        return NASDisk(mnt: mnt, fs: fs, used: used, total: total, pct: pct, kind: kind)
    }

    private func byteText(_ b: Double) -> String {
        if b >= 1_073_741_824 { return String(format: "%.1fG", b / 1_073_741_824) }
        if b >= 1_048_576 { return String(format: "%.0fM", b / 1_048_576) }
        return String(format: "%.0fK", b / 1024)
    }
}

// MARK: - HA 实体（/api/ha/states）

struct HAEntity: Identifiable {
    let entityID: String
    let state: String
    let friendlyName: String
    let attributes: [String: Any]

    var id: String { entityID }

    static func parse(_ d: [String: Any]) -> HAEntity? {
        guard let eid = d["entity_id"] as? String else { return nil }
        let attrs = d["attributes"] as? [String: Any] ?? [:]
        let fn = attrs["friendly_name"] as? String ?? ""
        return HAEntity(entityID: eid, state: d["state"] as? String ?? "", friendlyName: fn, attributes: attrs)
    }
}

// MARK: - v3.0.27 会话文件夹/标签

/// 会话分类（本地存储，UserDefaults JSON）
struct SessionCategory: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var icon: String     // SF Symbol name
    var color: String    // hex color string
}

/// 会话分类管理（UserDefaults 持久化）
@MainActor
@Observable
final class CategoryStore {
    var categories: [SessionCategory] = []
    var sessionCategories: [String: String] = [:]  // sessionId → categoryId

    private let categoriesKey = "qingliao_categories"
    private let mappingKey = "qingliao_session_categories"

    init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let cats = try? JSONDecoder().decode([SessionCategory].self, from: data) {
            categories = cats
        }
        if let data = UserDefaults.standard.data(forKey: mappingKey),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            sessionCategories = map
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
        if let data = try? JSONEncoder().encode(sessionCategories) {
            UserDefaults.standard.set(data, forKey: mappingKey)
        }
    }

    func addCategory(_ cat: SessionCategory) {
        categories.append(cat)
        save()
    }

    func removeCategory(_ id: String) {
        categories.removeAll { $0.id == id }
        sessionCategories = sessionCategories.filter { $0.value != id }
        save()
    }

    func assignSession(_ sessionId: String, to categoryId: String?) {
        if let catId = categoryId {
            sessionCategories[sessionId] = catId
        } else {
            sessionCategories.removeValue(forKey: sessionId)
        }
        save()
    }

    func categoryForSession(_ sessionId: String) -> SessionCategory? {
        guard let catId = sessionCategories[sessionId] else { return nil }
        return categories.first { $0.id == catId }
    }
}
