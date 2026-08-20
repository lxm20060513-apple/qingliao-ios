import Foundation
import UIKit
import EventKit
import UserNotifications

// MARK: - v3.0.18 云端模式本地工具集（function calling）
// 模型返回 tool_calls → LocalToolRunner 执行手机本地工具 → 结果回传模型继续对话。
// 与 NAS 后端无关（纯 App 内闭环），所有工具运行在主线程（EventKit/UIPasteboard 主线程安全）。

/// 解析后的工具调用（非流式响应 / 流式合并后的完整形态）
struct ParsedToolCall {
    var id: String
    var name: String
    var arguments: String      // JSON 字符串（对象）
}

/// 工具执行结果
struct ToolResult {
    var success: Bool
    var summary: String        // 展示用简短文本（工具卡片）
    var detail: String = ""    // 回传给模型的完整 JSON 文本（已是 JSON 字符串）
}

/// 工具定义（OpenAI function schema）
struct LocalToolDef {
    let name: String
    let description: String
    let parameters: [String: Any]
    let needsConfirm: Bool     // true = 写操作，执行前弹确认框
    let run: ([String: Any]) -> ToolResult
}

/// 本地工具集：注册表 + 执行
/// v3.0.18：@MainActor——工具都涉及 UIKit/EventKit/UserNotifications，须主线程
@MainActor
enum LocalToolRunner {
    /// 所有工具定义（OpenAI tools 数组格式）
    static let allDefs: [LocalToolDef] = [
        createReminderDef,
        createCalendarEventDef,
        startTimerDef,
        getWeatherDef,
        setClipboardDef,
        calculateDef,
        sendNotificationDef,
    ]

    /// OpenAI 协议 tools 数组（传给 /chat/completions）
    static var openAITools: [[String: Any]] {
        allDefs.map { def in
            [
                "type": "function",
                "function": [
                    "name": def.name,
                    "description": def.description,
                    "parameters": def.parameters,
                ],
            ]
        }
    }

    /// 按名字执行工具（找不到 → 失败结果）
    static func run(name: String, argumentsJSON: String) -> ToolResult {
        guard let def = allDefs.first(where: { $0.name == name }) else {
            return ToolResult(success: false, summary: "未知工具：\(name)", detail: #"{"error": "unknown tool"}"#)
        }
        // 解析 arguments JSON（容错：空串/非法 → 空字典）
        var args: [String: Any] = [:]
        if !argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let data = argumentsJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = obj
        }
        return def.run(args)
    }

    /// v3.0.18：异步执行入口——EventKit/通知类工具先请求系统权限再执行；天气走异步网络（避免主线程阻塞）
    static func execute(name: String, argumentsJSON: String) async -> ToolResult {
        // 天气：异步网络请求（不用 run 闭包里的 DispatchSemaphore——@MainActor 下会卡死主线程）
        if name == "get_weather" {
            var args: [String: Any] = [:]
            if let data = argumentsJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                args = obj
            }
            let city = (args["city"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return await fetchWeatherAsync(city: city)
        }
        // 权限预检（iOS 17+ API；部署目标 26 无兼容问题）
        switch name {
        case "create_calendar_event":
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                let store = EKEventStore()
                store.requestFullAccessToEvents { ok, _ in cont.resume(returning: ok) }
            }
            guard granted else {
                return ToolResult(success: false, summary: "日历权限被拒绝（设置 → 隐私 → 日历 开启）",
                                  detail: #"{"error": "calendar permission denied"}"#)
            }
        case "create_reminder":
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                let store = EKEventStore()
                store.requestFullAccessToReminders { ok, _ in cont.resume(returning: ok) }
            }
            guard granted else {
                return ToolResult(success: false, summary: "提醒权限被拒绝（设置 → 隐私 → 提醒事项 开启）",
                                  detail: #"{"error": "reminder permission denied"}"#)
            }
        case "start_timer", "send_notification":
            // v3.0.18 review fix #4：通知权限预检——denied 直接返回失败，不静默丢通知
            let center = UNUserNotificationCenter.current()
            let status = await withCheckedContinuation { (cont: CheckedContinuation<UNAuthorizationStatus, Never>) in
                center.getNotificationSettings { settings in
                    cont.resume(returning: settings.authorizationStatus)
                }
            }
            guard status == .authorized || status == .provisional else {
                return ToolResult(success: false, summary: "通知权限被拒绝（设置 → 轻聊 → 通知 开启）",
                                  detail: #"{"error": "notification permission denied"}"#)
            }
        default:
            break
        }
        return run(name: name, argumentsJSON: argumentsJSON)
    }

    /// v3.0.18：天气异步查询（async/await 版，替代 run 闭包里的同步 semaphore）
    static func fetchWeatherAsync(city: String) async -> ToolResult {
        var lat = 22.54, lon = 114.06, cityName = "深圳"
        if !city.isEmpty {
            // geocoding 拿经纬度
            let enc = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            guard let gurl = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=1&language=zh&format=json") else {
                return ToolResult(success: false, summary: "天气服务地址无效", detail: #"{"error": "bad url"}"#)
            }
            do {
                let (gdata, _) = try await URLSession.shared.data(from: gurl)
                if let obj = try? JSONSerialization.jsonObject(with: gdata) as? [String: Any],
                   let results = obj["results"] as? [[String: Any]],
                   let first = results.first,
                   let glat = first["latitude"] as? Double,
                   let glon = first["longitude"] as? Double {
                    lat = glat
                    lon = glon
                    cityName = first["name"] as? String ?? city
                } else {
                    return ToolResult(success: false, summary: "未找到城市「\(city)」", detail: #"{"error": "city not found"}"#)
                }
            } catch {
                return ToolResult(success: false, summary: "天气查询失败", detail: #"{"error": "geocoding network"}"#)
            }
        }
        let fstr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=Asia%2FShanghai&forecast_days=1"
        guard let furl = URL(string: fstr) else {
            return ToolResult(success: false, summary: "天气服务地址无效", detail: #"{"error": "bad url"}"#)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: furl)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = obj["current"] as? [String: Any],
                  let temp = cur["temperature_2m"] as? Double else {
                return ToolResult(success: false, summary: "天气解析失败", detail: #"{"error": "parse"}"#)
            }
            let code = cur["weather_code"] as? Int ?? 0
            let daily = obj["daily"] as? [String: Any]
            let maxT = (daily?["temperature_2m_max"] as? [Double])?.first
            let minT = (daily?["temperature_2m_min"] as? [Double])?.first
            var parts = ["当前 \(Int(temp))°C", weatherText(code)]
            if let maxT, let minT {
                parts.append("今日 \(Int(minT))°~\(Int(maxT))°")
            }
            return ToolResult(success: true,
                              summary: "\(cityName)天气：\(parts.joined(separator: " · "))",
                              detail: #"{"ok": true, "temp": \#(temp), "code": \#(code)}"#)
        } catch {
            return ToolResult(success: false, summary: "天气查询失败", detail: #"{"error": "network"}"#)
        }
    }

    static func needsConfirm(name: String) -> Bool {
        allDefs.first(where: { $0.name == name })?.needsConfirm ?? false
    }

    // MARK: - 工具实现

    /// 📅 日历建事件
    static let createCalendarEventDef = LocalToolDef(
        name: "create_calendar_event",
        description: "在系统日历中创建一条日程事件。用户说「X号X点做某事」且明确是日程时使用。返回创建结果。",
        parameters: [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "事件标题，如：开会"],
                "start": ["type": "string", "description": "开始时间，格式如 2026-08-21T15:00:00 或 2026-08-21 15:00（本地时间，无时区）"],
                "end": ["type": "string", "description": "结束时间，格式同上；可省略默认 1 小时"],
                "notes": ["type": "string", "description": "备注，可选"],
            ],
            "required": ["title", "start"],
        ],
        needsConfirm: true,
        run: { args in
            guard let title = args["title"] as? String, !title.isEmpty,
                  let startStr = args["start"] as? String,
                  let start = ISO8601DateFormatter().date(from: startStr) ?? Self.parseFlexibleDate(startStr) else {
                return ToolResult(success: false, summary: "日历事件缺少标题或时间",
                                  detail: #"{"error": "missing title or start"}"#)
            }
            let store = EKEventStore()
            let end: Date
            if let endStr = args["end"] as? String,
               let e = ISO8601DateFormatter().date(from: endStr) ?? Self.parseFlexibleDate(endStr) {
                end = e
            } else {
                end = start.addingTimeInterval(3600)
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = end
            event.calendar = store.defaultCalendarForNewEvents
            if let notes = args["notes"] as? String, !notes.isEmpty { event.notes = notes }
            do {
                try store.save(event, span: .thisEvent)
                let f = DateFormatter()
                f.dateFormat = "M月d日 HH:mm"
                return ToolResult(success: true,
                                  summary: "已创建日程：\(title)（\(f.string(from: start))）",
                                  detail: #"{"ok": true, "title": "\#(title)", "start": "\#(startStr)"}"#)
            } catch {
                return ToolResult(success: false, summary: "日历创建失败：\(error.localizedDescription)",
                                  detail: #"{"error": "\#(error.localizedDescription)"}"#)
            }
        }
    )

    /// ⏰ 提醒
    static let createReminderDef = LocalToolDef(
        name: "create_reminder",
        description: "创建一条提醒事项（系统提醒，到时间通知）。用户说「提醒我X点做某事」时使用。",
        parameters: [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "提醒内容，如：开会"],
                "due": ["type": "string", "description": "提醒时间，格式如 2026-08-21T15:00:00 或 2026-08-21 15:00（本地时间，无时区）"],
                "minutes": ["type": "integer", "description": "相对当前时间的分钟数（如 10 = 10分钟后）；与 due 二选一"],
            ],
            "required": ["title"],
        ],
        needsConfirm: true,
        run: { args in
            guard let title = args["title"] as? String, !title.isEmpty else {
                return ToolResult(success: false, summary: "提醒缺少内容",
                                  detail: #"{"error": "missing title"}"#)
            }
            var due: Date?
            if let dueStr = args["due"] as? String {
                due = ISO8601DateFormatter().date(from: dueStr) ?? Self.parseFlexibleDate(dueStr)
            } else if let mins = args["minutes"] as? Int {
                due = Date().addingTimeInterval(TimeInterval(mins * 60))
            }
            let store = EKEventStore()
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = store.defaultCalendarForNewReminders()
            if let due {
                let alarm = EKAlarm(absoluteDate: due)
                reminder.addAlarm(alarm)
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: due)
            }
            do {
                try store.save(reminder, commit: true)
                let f = DateFormatter()
                f.dateFormat = "M月d日 HH:mm"
                let whenText = due.map { f.string(from: $0) } ?? "尽快"
                return ToolResult(success: true,
                                  summary: "已创建提醒：\(title)（\(whenText)）",
                                  detail: #"{"ok": true, "title": "\#(title)", "due": "\#(due?.timeIntervalSince1970 ?? 0)}"#)
            } catch {
                return ToolResult(success: false, summary: "提醒创建失败：\(error.localizedDescription)",
                                  detail: #"{"error": "\#(error.localizedDescription)"}"#)
            }
        }
    )

    /// ⏱️ 计时器（本地通知）
    static let startTimerDef = LocalToolDef(
        name: "start_timer",
        description: "启动一个倒计时计时器，到时间发本地通知。用户说「X分钟后提醒我/计时X分钟」时使用。",
        parameters: [
            "type": "object",
            "properties": [
                "seconds": ["type": "integer", "description": "倒计时秒数（如 300 = 5分钟）"],
                "label": ["type": "string", "description": "计时器名称，可选，如：煮面"],
            ],
            "required": ["seconds"],
        ],
        needsConfirm: true,
        run: { args in
            guard let secs = args["seconds"] as? Int, secs > 0 else {
                return ToolResult(success: false, summary: "计时器需要有效秒数",
                                  detail: #"{"error": "invalid seconds"}"#)
            }
            let label = (args["label"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let content = UNMutableNotificationContent()
            content.title = "⏱️ 计时器"
            content.body = label.isEmpty ? "倒计时 \(secs) 秒结束" : "「\(label)」倒计时结束"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(secs), repeats: false)
            let req = UNNotificationRequest(identifier: "timer_\(Int(Date().timeIntervalSince1970))",
                                            content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req)
            let minutes = secs / 60
            let secsLeft = secs % 60
            let whenText = minutes > 0 ? "\(minutes)分\(secsLeft)秒" : "\(secsLeft)秒"
            return ToolResult(success: true,
                              summary: "计时器已启动：\(label.isEmpty ? "\(whenText)倒计时" : label)（\(whenText)后通知）",
                              detail: #"{"ok": true, "seconds": \#(secs), "label": "\#(label)"}"#)
        }
    )

    /// 🌤️ 天气（异步实现见 fetchWeatherAsync；run 闭包仅占位——execute 拦截 get_weather 走异步）
    static let getWeatherDef = LocalToolDef(
        name: "get_weather",
        description: "查询天气（当前温度 + 今日天气）。用户问天气、冷不冷、要不要带伞时使用。城市可选：给中文城市名（如 北京、深圳）；省略默认深圳（用户所在城市）。",
        parameters: [
            "type": "object",
            "properties": [
                "city": ["type": "string", "description": "城市名（中文，如 北京、深圳）；省略则用定位城市"],
            ],
        ],
        needsConfirm: false,
        run: { _ in
            // 实际由 execute() 的 fetchWeatherAsync 分支处理（@MainActor 下同步网络会卡死）
            ToolResult(success: false, summary: "天气查询中…", detail: #"{"ok": false, "async": true}"#)
        }
    )

    /// 📋 剪贴板
    static let setClipboardDef = LocalToolDef(
        name: "set_clipboard",
        description: "把文本写入系统剪贴板。用户说「复制XX」「把XX复制下来」时使用。",
        parameters: [
            "type": "object",
            "properties": [
                "text": ["type": "string", "description": "要复制的文本"],
            ],
            "required": ["text"],
        ],
        needsConfirm: false,
        run: { args in
            guard let text = args["text"] as? String else {
                return ToolResult(success: false, summary: "剪贴板内容为空",
                                  detail: #"{"error": "empty text"}"#)
            }
            UIPasteboard.general.string = text
            let preview = text.count > 20 ? String(text.prefix(20)) + "…" : text
            return ToolResult(success: true,
                              summary: "已复制：\(preview)",
                              detail: #"{"ok": true, "chars": \#(text.count)}"#)
        }
    )

    /// 🧮 计算器（安全求值：仅数字/四则/括号/小数点，防注入）
    static let calculateDef = LocalToolDef(
        name: "calculate",
        description: "执行数学计算（四则运算、括号、小数、百分比）。用户问算术、换算、折扣时使用。",
        parameters: [
            "type": "object",
            "properties": [
                "expression": ["type": "string", "description": "数学表达式，如 (120*0.85)+10"],
            ],
            "required": ["expression"],
        ],
        needsConfirm: false,
        run: { args in
            guard let expr = args["expression"] as? String else {
                return ToolResult(success: false, summary: "缺少表达式", detail: #"{"error": "missing expression"}"#)
            }
            let cleaned = expr.replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "＋", with: "+")
                .replacingOccurrences(of: "－", with: "-")
                .replacingOccurrences(of: " ", with: "")
            // 白名单字符检查（数字 0-9 . + - * / ( ) %）
            let allowed = CharacterSet(charactersIn: "0123456789.+-*/()%")
            guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                return ToolResult(success: false, summary: "表达式包含非法字符",
                                  detail: #"{"error": "invalid characters"}"#)
            }
            // v3.0.18：% 在 NSExpression(format:) 是 C 风格格式符（%d 等），字面 % 须转义 %% 防格式串注入/崩溃
            let safeExpr = cleaned.replacingOccurrences(of: "%", with: "%%")
            let exp = NSExpression(format: safeExpr)
            guard let value = exp.expressionValue(with: nil, context: nil) as? NSNumber else {
                return ToolResult(success: false, summary: "无法计算该表达式",
                                  detail: #"{"error": "cannot evaluate"}"#)
            }
            let v = value.doubleValue
            // v3.0.18：整数直接显示；小数保留 4 位去尾零（用 (?<!\\d) 防把整数的尾零删掉，如 100→"1"）
            let text: String
            if v == v.rounded() {
                text = String(Int(v))
            } else {
                let trimmed = String(format: "%.4f", v).replacingOccurrences(of: "(\\.\\d*?)0+$", with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
                text = trimmed
            }
            return ToolResult(success: true,
                              summary: "\(expr) = \(text)",
                              detail: #"{"ok": true, "expression": "\#(expr)", "result": "\#(v)"}"#)
        }
    )

    /// 🔔 本地通知（立即通知）
    static let sendNotificationDef = LocalToolDef(
        name: "send_notification",
        description: "立即发送一条本地通知（App 内弹通知）。用户说「通知我/提醒我」且无具体时间时使用。",
        parameters: [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "通知标题，可选"],
                "body": ["type": "string", "description": "通知内容"],
            ],
            "required": ["body"],
        ],
        needsConfirm: false,
        run: { args in
            guard let body = args["body"] as? String, !body.isEmpty else {
                return ToolResult(success: false, summary: "通知内容为空", detail: #"{"error": "empty body"}"#)
            }
            let title = (args["title"] as? String) ?? "轻聊"
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(identifier: "local_\(Int(Date().timeIntervalSince1970))",
                                            content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
            return ToolResult(success: true,
                              summary: "已发送通知：\(body)",
                              detail: #"{"ok": true, "body": "\#(body)"}"#)
        }
    )

    // MARK: - 辅助

    /// 宽松时间解析（支持 "2026-08-21 15:00:00" / "2026-08-21T15:00:00" / "2026-08-21 15:00" /
    /// "2026-08-21T15:00" / "MM-dd HH:mm" / "HH:mm"（已过则明天））
    static func parseFlexibleDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .current
        // v3.0.18 review fix：带秒模式必须在前（模型按 schema 示例输出 "2026-08-21T15:00:00"，
        // 无秒模式 "yyyy-MM-dd'T'HH:mm" 吞不下尾部 ":00" → 解析失败）
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm", "MM-dd HH:mm", "HH:mm",
        ]
        for p in patterns {
            f.dateFormat = p
            if let d = f.date(from: s) { return d }
        }
        // 纯 HH:mm → 今天（若已过则明天）
        f.dateFormat = "HH:mm"
        if let d = f.date(from: s) {
            let cal = Calendar.current
            var comps = cal.dateComponents([.hour, .minute], from: d)
            let now = Date()
            comps.year = cal.component(.year, from: now)
            comps.month = cal.component(.month, from: now)
            comps.day = cal.component(.day, from: now)
            var target = cal.date(from: comps) ?? now
            if target < now { target = cal.date(byAdding: .day, value: 1, to: target) ?? now }
            return target
        }
        return nil
    }

    /// WMO 天气码 → 中文描述
    static func weatherText(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67: return "雨"
        case 71, 73, 75, 77: return "雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95, 96, 99: return "雷暴"
        default: return ""
        }
    }
}
