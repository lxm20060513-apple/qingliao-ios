import Foundation

// MARK: - v3.0.18 云端工具循环（function calling 编排）
//
// 流程：
//  1. 首轮：streamChat(messages, tools) 流式——模型边思考边输出文本，末尾可能带 tool_calls
//  2. 有 tool_calls → 逐条确认（写操作）→ 执行本地工具 → 结果以 role:"tool" 追加
//  3. 下一轮：toolChat（非流式，等模型基于结果生成最终文本）
//  4. 最多 3 轮工具循环，防止死循环
//
// 与 ChatView.startCloudStream 的分工：
//  - 本类只负责「模型 ↔ 工具」的对话编排，产出最终文本增量流
//  - UI（streamingBubble、工具卡片、确认弹窗）由 ChatView 处理

/// 工具循环的单步结果
enum CloudLoopEvent {
    case text(String)                       // 模型文本增量（首轮流式）
    case toolCard(title: String, ok: Bool)  // 工具执行完毕卡片（UI 展示用）
    case done(String)                       // 全部完成，最终文本
    case error(String)                      // 出错（中止）
}

/// 需要用户确认的工具调用（写操作）
struct PendingToolConfirm {
    let call: ParsedToolCall
    let summary: String
}

/// 云端工具循环编排器
@MainActor
final class CloudToolLoop {
    static let shared = CloudToolLoop()

    /// 工具开关（设置页 qingliao_cloud_tools，默认开）
    var toolsEnabled: Bool {
        UserDefaults.standard.object(forKey: "qingliao_cloud_tools") as? Bool ?? true
    }

    private init() {}

    /// 执行一轮带工具循环的对话。
    /// - Parameters:
    ///   - messages: 完整对话历史（含用户最新消息）
    ///   - confirmHandler: 写操作确认回调（async：返回 true=用户同意执行）。nil = 不确认直接执行
    ///   - events: 事件回调（主线程）
    /// - Returns: 最终文本（供落库）；nil = 出错/取消
    func run(messages: [[String: Any]],
             confirmHandler: ((PendingToolConfirm) async -> Bool)?,
             events: @escaping (CloudLoopEvent) -> Void) async -> String? {
        // 工具关闭 → 纯文本流式（原行为）
        guard toolsEnabled else {
            var full = ""
            do {
                for try await chunk in CloudBackend.shared.streamChat(messages: messages) {
                    if !chunk.error.isEmpty {
                        events(.error(chunk.error))
                        return nil
                    }
                    if !chunk.contentDelta.isEmpty {
                        full += chunk.contentDelta
                        events(.text(chunk.contentDelta))
                    }
                    if chunk.done { break }
                }
                events(.done(full))
                return full
            } catch {
                events(.error(error.localizedDescription))
                return nil
            }
        }

        var working = messages
        // 分片 tool_calls 累积器（流式：同一 index 多次出现）
        struct PendingCall {
            var id: String = ""
            var name: String = ""
            var args: String = ""
        }
        var pendingCalls: [Int: PendingCall] = [:]
        // v3.0.18 review fix #2：跨轮累计最终全文（.done 事件是纯信号，返回值必须含首轮叙述）
        var accumulatedFull = ""

        // ── 第 1 轮：流式（带 tools）
        var full = ""
        do {
            for try await chunk in CloudBackend.shared.streamChat(messages: working, tools: LocalToolRunner.openAITools) {
                if !chunk.error.isEmpty {
                    events(.error(chunk.error))
                    return nil
                }
                if !chunk.contentDelta.isEmpty {
                    full += chunk.contentDelta
                    accumulatedFull += chunk.contentDelta
                    events(.text(chunk.contentDelta))
                }
                for tc in chunk.toolCalls {
                    var entry = pendingCalls[tc.index] ?? PendingCall()
                    if !tc.id.isEmpty { entry.id = tc.id }
                    if !tc.name.isEmpty { entry.name = tc.name }
                    entry.args += tc.arguments
                    pendingCalls[tc.index] = entry
                }
                if chunk.done { break }
            }
        } catch {
            events(.error(error.localizedDescription))
            return nil
        }

        // 无工具调用 → 直接完成
        let calls = pendingCalls.values.map {
            ParsedToolCall(id: $0.id, name: $0.name, arguments: $0.args)
        }
        if calls.isEmpty {
            events(.done(full))
            return full
        }

        // 追加 assistant 消息（含 tool_calls，OpenAI 协议要求保留）
        // v3.0.84fix：content 为空时不写入键（原写 nil 入 [String:Any] 字典，JSONSerialization 序列化必崩）
        var assistantMsg: [String: Any] = ["role": "assistant"]
        if !full.isEmpty { assistantMsg["content"] = full }
        assistantMsg["tool_calls"] = calls.map { c in
            [
                "id": c.id,
                "type": "function",
                "function": ["name": c.name, "arguments": c.arguments],
            ]
        }
        working.append(assistantMsg)

        // ── 执行工具（写操作先确认）
        for c in calls {
            let needsConfirm = LocalToolRunner.needsConfirm(name: c.name)
            let preview = toolPreview(c)
            if needsConfirm, let confirmHandler {
                let ok = await confirmHandler(PendingToolConfirm(call: c, summary: preview))
                guard ok else {
                    working.append(["role": "tool", "tool_call_id": c.id,
                                    "content": #"{"cancelled": true, "error": "用户取消"}"#])
                    events(.toolCard(title: "已取消：\(preview)", ok: false))
                    continue
                }
            }
            let result = await LocalToolRunner.execute(name: c.name, argumentsJSON: c.arguments)
            events(.toolCard(title: result.summary, ok: result.success))
            working.append(["role": "tool", "tool_call_id": c.id,
                            "content": result.detail])
        }

        // ── 第 2+ 轮：非流式等最终文本（最多再 2 轮工具）
        for round in 1...2 {
            let (text, newCalls, err) = await CloudBackend.shared.toolChat(messages: working, tools: LocalToolRunner.openAITools)
            if !err.isEmpty {
                events(.error(err))
                return nil
            }
            if newCalls.isEmpty {
                if !text.isEmpty {
                    accumulatedFull += text
                    events(.text(text))
                }
                // v3.0.18 review fix #2：.done 携带累计全文（含首轮叙述），不再只传本轮
                events(.done(accumulatedFull))
                return accumulatedFull
            }
            // 又一批工具调用
            if !text.isEmpty {
                accumulatedFull += text
                events(.text(text))
            }
            // v3.0.84fix：content 为空时不写入键（原写 nil 入字典，序列化崩溃）
            var assistantAppend: [String: Any] = ["role": "assistant"]
            if !text.isEmpty { assistantAppend["content"] = text }
            assistantAppend["tool_calls"] = newCalls.map { c in
                ["id": c.id, "type": "function",
                 "function": ["name": c.name, "arguments": c.arguments]]
            }
            working.append(assistantAppend)
            for c in newCalls {
                let needsConfirm = LocalToolRunner.needsConfirm(name: c.name)
                let preview = toolPreview(c)
                if needsConfirm, let confirmHandler {
                    let ok = await confirmHandler(PendingToolConfirm(call: c, summary: preview))
                    guard ok else {
                        working.append(["role": "tool", "tool_call_id": c.id,
                                        "content": #"{"cancelled": true, "error": "用户取消"}"#])
                        events(.toolCard(title: "已取消：\(preview)", ok: false))
                        continue
                    }
                }
                let result = await LocalToolRunner.execute(name: c.name, argumentsJSON: c.arguments)
                events(.toolCard(title: result.summary, ok: result.success))
                working.append(["role": "tool", "tool_call_id": c.id,
                                "content": result.detail])
            }
        }

        // 3 轮上限用尽 → 用现有消息再问一次拿最终文本
        let (text, _, err) = await CloudBackend.shared.toolChat(messages: working, tools: nil)
        if !err.isEmpty {
            events(.error(err))
            return nil
        }
        if !text.isEmpty {
            accumulatedFull += text
            events(.text(text))
        }
        events(.done(accumulatedFull))
        return accumulatedFull
    }

    /// 工具调用的人类可读预览（确认弹窗/卡片标题用）
    private func toolPreview(_ c: ParsedToolCall) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(c.arguments.utf8))) as? [String: Any] ?? [:]
        switch c.name {
        case "create_calendar_event":
            let t = args["title"] as? String ?? "?"
            return "📅 创建日程：\(t)"
        case "create_reminder":
            let t = args["title"] as? String ?? "?"
            if let due = args["due"] as? String { return "⏰ 提醒：\(t)（\(due)）" }
            if let m = args["minutes"] as? Int { return "⏰ 提醒：\(t)（\(m) 分钟后）" }
            return "⏰ 提醒：\(t)"
        case "start_timer":
            let s = args["seconds"] as? Int ?? 0
            let label = args["label"] as? String ?? ""
            let text = label.isEmpty ? "\(s) 秒" : "「\(label)」\(s) 秒"
            return "⏱️ 启动计时器：\(text)"
        case "get_weather":
            let city = args["city"] as? String ?? "当前城市"
            return "🌤️ 查询天气：\(city)"
        case "set_clipboard":
            let t = args["text"] as? String ?? ""
            let preview = t.count > 16 ? String(t.prefix(16)) + "…" : t
            return "📋 复制到剪贴板：\(preview)"
        case "calculate":
            let e = args["expression"] as? String ?? "?"
            return "🧮 计算：\(e)"
        case "send_notification":
            let b = args["body"] as? String ?? "?"
            return "🔔 发送通知：\(b)"
        default:
            return "🔧 \(c.name)"
        }
    }
}
