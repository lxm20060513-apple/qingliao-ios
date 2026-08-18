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
    var done: Bool = false
    var error: String = ""
}

/// CloudBackend：直连 OpenAI 兼容 /chat/completions 流式接口
/// 数据模型复用 ChatMessage/ChatStore（UI 层零改动）
@MainActor
@Observable
final class CloudBackend {
    static let shared = CloudBackend()

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
    func streamChat(messages: [[String: Any]]) -> AsyncThrowingStream<CloudStreamChunk, Error> {
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
                req.httpBody = try? JSONSerialization.data(withJSONObject: [
                    "model": config.model,
                    "messages": messages,
                    "stream": true,
                ])
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
                            break
                        }
                        if let choices = obj["choices"] as? [[String: Any]],
                           let first = choices.first {
                            if let delta = first["delta"] as? [String: Any],
                               let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(CloudStreamChunk(contentDelta: text))
                            } else if let delta = first["delta"] as? [String: Any],
                                      let content = delta["content"] as? String, !content.isEmpty {
                                continuation.yield(CloudStreamChunk(contentDelta: content))
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
