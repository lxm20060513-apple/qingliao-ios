import Foundation

// MARK: - v3.0 云端直连后端：OpenAI 兼容 chat/completions SSE 流式

/// 云端直连错误
enum CloudAPIError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "云端模型未配置（请先在登录页添加 API Key）"
        case .badURL: return "API 地址无效"
        case .http(let code, let msg): return "云端返回错误 (HTTP \(code))\(msg.isEmpty ? "" : "：\(msg)")"
        case .invalidResponse: return "云端响应解析失败"
        }
    }
}

/// 云端流式结果
struct CloudStreamChunk {
    var contentDelta: String = ""      // 增量文本
    var toolCalls: [CloudToolCall] = []   // v3.0.18：本 chunk 的 tool_calls 增量（流式分片，需按 index 合并）
    var done: Bool = false
    var error: String = ""
}

/// v3.0.18：工具调用（流式分片增量，index 相同表示同一调用的分段 arguments）
struct CloudToolCall {
    var index: Int
    var id: String = ""          // 分片只在首片带 id，后续片为空需沿用
    var name: String = ""        // 同上
    var arguments: String = ""   // JSON 字符串增量
}

/// CloudBackend：直连 OpenAI 兼容 /chat/completions 流式接口
/// 数据模型复用 ChatMessage/ChatStore（UI 层零改动）
@MainActor
@Observable
final class CloudBackend {
    static let shared = CloudBackend()

    // v3.0.2：云端流式进行中标记（驱动 Siri 边框发光等 isStreaming 相关 UI）
    var isStreaming = false

    private var session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// 连通性测试：调 /models 或最小 chat 请求验证 key 有效
    func testConnection(config: CloudProviderConfig) async -> (Bool, String) {
        guard let url = URL(string: config.baseURL + "/chat/completions") else {
            return (false, "API 地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": config.model.isEmpty ? "test" : config.model,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false,
        ])
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                return (true, "✅ 连接正常（\(config.name) · \(config.model)）")
            }
            let msg = String(data: data, encoding: .utf8) ?? ""
            let brief = String(msg.prefix(200))
            if code == 401 || code == 403 {
                return (false, "❌ API Key 无效（HTTP \(code)）")
            }
            return (false, "⚠️ 服务器返回 \(code)：\(brief)")
        } catch {
            return (false, "❌ 无法连接：\(error.localizedDescription)")
        }
    }

    /// SSE 流式对话（AsyncThrowingStream：逐 chunk 吐出增量文本，流结束 done=true）
    /// v3.0.18：支持 tools（function calling）——请求带 tools 数组，响应解析 delta.tool_calls
    func streamChat(messages: [[String: Any]], tools: [[String: Any]]? = nil) -> AsyncThrowingStream<CloudStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                guard let config = CloudConfig.shared.activeConfig, config.isValidForChat else {
                    continuation.yield(CloudStreamChunk(error: "云端模型未配置"))
                    continuation.finish()
                    return
                }
                guard let url = URL(string: config.baseURL + "/chat/completions") else {
                    continuation.yield(CloudStreamChunk(error: CloudAPIError.badURL.localizedDescription))
                    continuation.finish()
                    return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 60
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                var body: [String: Any] = [
                    "model": config.model,
                    "messages": messages,
                    "stream": true,
                ]
                if let tools, !tools.isEmpty {
                    body["tools"] = tools
                }
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line
                            if errBody.count > 500 { break }
                        }
                        continuation.yield(CloudStreamChunk(
                            error: CloudAPIError.http(code, String(errBody.prefix(300))).localizedDescription))
                        continuation.finish()
                        return
                    }
                    // SSE 解析：data: {...} 行，[DONE] 结束
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            break
                        }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let err = obj["error"] as? [String: Any] {
                            let msg = err["message"] as? String ?? "未知错误"
                            continuation.yield(CloudStreamChunk(error: msg))
                            // v3.0.5 review fix：error 后直接 finish，避免循环外再 yield(done:true) 双 chunk 语义重复
                            continuation.finish()
                            return
                        }
                        if let choices = obj["choices"] as? [[String: Any]],
                           let first = choices.first {
                            if let delta = first["delta"] as? [String: Any] {
                                // v3.0.18：tool_calls 增量（function calling 流式分片）
                                if let tcArr = delta["tool_calls"] as? [[String: Any]] {
                                    var calls: [CloudToolCall] = []
                                    for tc in tcArr {
                                        let idx = tc["index"] as? Int ?? 0
                                        var c = CloudToolCall(index: idx)
                                        if let id = tc["id"] as? String { c.id = id }
                                        if let fn = tc["function"] as? [String: Any] {
                                            if let name = fn["name"] as? String { c.name = name }
                                            if let args = fn["arguments"] as? String { c.arguments = args }
                                        }
                                        calls.append(c)
                                    }
                                    if !calls.isEmpty {
                                        continuation.yield(CloudStreamChunk(toolCalls: calls))
                                    }
                                }
                                // 文本增量（text 兼容旧端点 / content 标准）
                                if let text = delta["text"] as? String, !text.isEmpty {
                                    continuation.yield(CloudStreamChunk(contentDelta: text))
                                } else if let content = delta["content"] as? String, !content.isEmpty {
                                    continuation.yield(CloudStreamChunk(contentDelta: content))
                                }
                            }
                            if let finish = first["finish_reason"] as? String, !finish.isEmpty {
                                break
                            }
                        }
                    }
                    continuation.yield(CloudStreamChunk(done: true))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(CloudStreamChunk(error: error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// v3.0.18：非流式工具循环请求（执行工具后回传结果，等模型最终文本）
    /// 返回 {content, toolCalls:[{id,name,arguments}]}；流式已在 streamChat 覆盖，此方法供工具循环第二+轮使用
    func toolChat(messages: [[String: Any]], tools: [[String: Any]]?) async -> (content: String, toolCalls: [ParsedToolCall], error: String) {
        guard let config = CloudConfig.shared.activeConfig, config.isValidForChat,
              let url = URL(string: config.baseURL + "/chat/completions") else {
            return ("", [], "云端模型未配置")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": false,
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any] else {
                return ("", [], "云端返回异常 (HTTP \(code))")
            }
            let content = msg["content"] as? String ?? ""
            var calls: [ParsedToolCall] = []
            if let tcArr = msg["tool_calls"] as? [[String: Any]] {
                for tc in tcArr {
                    guard let fn = tc["function"] as? [String: Any] else { continue }
                    calls.append(ParsedToolCall(id: tc["id"] as? String ?? "",
                                               name: fn["name"] as? String ?? "",
                                               arguments: fn["arguments"] as? String ?? "{}"))
                }
            }
            return (content, calls, "")
        } catch {
            return ("", [], error.localizedDescription)
        }
    }

    /// 拉取当前 API 可用模型列表（OpenAI 兼容 /models 端点）——对齐本地模型管理
    func fetchModels() async -> ([String], String?) {
        guard let config = CloudConfig.shared.activeConfig,
              !config.baseURL.isEmpty, !config.apiKey.isEmpty,
              let url = URL(string: config.baseURL + "/models") else {
            return ([], "云端模型未配置")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["data"] as? [[String: Any]] else {
                return ([], "无法获取模型列表 (HTTP \(code))")
            }
            let ids = arr.compactMap { $0["id"] as? String }.sorted()
            return (ids, nil)
        } catch {
            return ([], "无法连接：\(error.localizedDescription)")
        }
    }

    /// 非流式单次对话（用于标题生成等）
    func simpleChat(messages: [[String: Any]], maxTokens: Int = 30) async -> String? {
        guard let config = CloudConfig.shared.activeConfig, config.isValidForChat,
              let url = URL(string: config.baseURL + "/chat/completions") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": false,
        ])
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let text = msg["content"] as? String else { return nil }
            return text
        } catch {
            return nil
        }
    }
}

// MARK: - 配置有效性扩展

extension CloudProviderConfig {
    var isValidForChat: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
}
