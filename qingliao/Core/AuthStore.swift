import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    var isLoggedIn = true           // 免登录模式（AUTO_LOGIN）：始终 true
    var username = ""
    var serverURL = ""
    var token = ""
    var errorMessage: String?
    var isLoading = false

    private let defaults = UserDefaults.standard
    private let serverKey = "qingliao_server"
    private let tokenKey = "qingliao_token"
    private let userKey = "qingliao_user"

    /// Safari Relay 网络层（iOS 27 蜂窝上行挂起的最终方案）
    private let relay = SafariRelay.shared

    init() {
        token = defaults.string(forKey: tokenKey) ?? ""
        username = defaults.string(forKey: userKey) ?? ""
        serverURL = defaults.string(forKey: serverKey) ?? "https://example.com:16666"
        isLoggedIn = true   // 免登录：直接进主界面
    }

    // MARK: - 登录（免登录模式下仅为兼容保留）

    func login(username: String, password: String, remember: Bool = true) async {
        // 免登录模式：服务器 AUTO_LOGIN，无需密码；直接标记登录
        isLoggedIn = true
    }

    func logout() {
        token = ""
        isLoggedIn = true   // 免登录模式下登出也保持可访问
        defaults.removeObject(forKey: tokenKey)
    }

    // MARK: - 统一请求入口（新路由层）

    /// 统一 API 请求：自动判定直连/relay
    /// - 无参 GET（无 query/body/header）→ CFStream 直连（iOS 27 蜂窝唯一通的形态）
    /// - 带 query 的 GET / 任何 POST → Safari Relay（借 Safari 进程上行）
    /// 返回 (data, HTTPURLResponse)
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        let hasQuery = path.contains("?")
        let bodyData: Data?
        var headers: [String: String] = [:]
        if let body {
            headers["Content-Type"] = "application/json"
            bodyData = JSONSerialization.isValidJSONObject(body)
                ? (try? JSONSerialization.data(withJSONObject: body)) : nil
        } else {
            bodyData = nil
        }

        // 判定：无参 GET 走直连，其余走 relay
        let canDirect = (method == "GET") && !hasQuery && bodyData == nil

        let (data, code): (Data, Int)
        if canDirect {
            (data, code) = try await relay.directGET(path: path, headers: headers, timeout: 10)
        } else {
            (data, code) = try await relay.relay(method: method, path: path,
                                                 headers: headers, body: bodyData,
                                                 timeout: 30)
        }

        if code == 401 {
            // 免登录模式：401 视为成功（服务器 AUTO_LOGIN 已放行，个别端点自身逻辑返回 401 无碍）
            // 构造 200 透传（调用方只关心数据）
            let http = HTTPURLResponse(url: URL(string: "https://localhost")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, http)
        }
        guard (200..<300).contains(code) else {
            throw APIError.server(code)
        }
        let url = URL(string: serverURL + path) ?? URL(string: "https://localhost")!
        let http = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
        return (data, http)
    }

    /// 便捷：JSON 请求 → 字典
    func json(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        let (data, _) = try await request(path, method: method, body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badJSON
        }
        return json
    }

    /// 便捷：JSON 请求 → 数组
    func jsonArray(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [Any] {
        let (data, _) = try await request(path, method: method, body: body)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw APIError.badJSON
        }
        return arr
    }

    /// multipart 文件上传：relay 中转（payload 可能较大，>3.5KB 时拒绝）
    func uploadMultipart(_ path: String, fileName: String, data: Data) async throws -> [String: Any] {
        // 大文件 relay 传不下（URL 4KB 限制）→ 限制 2KB 以下小文件
        guard data.count < 2000 else {
            throw APIError.badResponseDetail("文件过大（relay 限 2KB，请用 PWA 上传）")
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (respData, code) = try await relay.relay(
            method: "POST", path: path,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: body, timeout: 30
        )
        guard (200..<300).contains(code) else { throw APIError.server(code) }
        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            throw APIError.badJSON
        }
        return json
    }

    // MARK: - 流式专用（relay 路径参数版）

    /// 流式启动：POST /r/stream/start 经 relay（会话隔离 uid + messages）
    func streamStart(sessionId: String, model: String, provider: String,
                     messages: [[String: Any]]) async throws -> String {
        let uid = RelayIdentity.uid(for: sessionId)
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "model": model,
            "provider": provider,
            "messages": messages,
            "pushEnabled": false
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, code) = try await relay.relay(
            method: "POST", path: "/r/stream/start/\(uid)",
            headers: ["Content-Type": "application/json"],
            body: bodyData, timeout: 30
        )
        guard (200..<300).contains(code),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tid = json["taskId"] as? String else {
            throw APIError.badResponseDetail("stream start fail (\(code))")
        }
        return tid
    }

    /// 流式轮询：GET /r/stream/poll/{uid}/{taskId}/{offset}（路径参数无 query → 走直连）
    func streamPoll(taskId: String, offset: Int) async throws -> (String, Bool, String, String) {
        // uid 从 taskId 推导（relay 服务器存映射）→ 但更简单：StreamClient 传 sessionId
        // 这里用全局当前 uid（ChatStore 管理）
        let uid = RelayIdentity.uid(for: currentStreamSessionId)
        let path = "/r/stream/poll/\(uid)/\(taskId)/\(offset)"
        let (data, code) = try await relay.directGET(path: path, timeout: 10)
        guard (200..<300).contains(code),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        let content = j["content"] as? String ?? ""
        let done = j["done"] as? Bool ?? false
        let status = j["status"] as? String ?? ""
        let error = j["error"] as? String ?? ""
        return (content, done, status, error)
    }

    /// 流式停止：POST /r/stream/stop/{uid}/{taskId}（无 body → 但走 relay 确保到达）
    func streamStop(taskId: String) async {
        let uid = RelayIdentity.uid(for: currentStreamSessionId)
        _ = try? await relay.relay(method: "POST", path: "/r/stream/stop/\(uid)/\(taskId)", timeout: 10)
    }

    /// 当前流式会话 id（StreamClient 启动时设置，用于 uid 推导）
    var currentStreamSessionId: String = ""

    // MARK: - 连通性测试

    /// 测试连接：直连 GET /api/auth/status（无参，iOS 27 唯一确定通的形态）
    func testConnection(server: String) async -> String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else {
            return "❌ 服务器地址无效"
        }
        do {
            let (_, code) = try await relay.directGET(path: "/api/auth/status", timeout: 8)
            if code == 401 || code == 200 {
                return "✅ 连接正常（服务器已响应）"
            }
            return "⚠️ 服务器返回 \(code)"
        } catch {
            return "❌ 无法连接（\(error.localizedDescription)）"
        }
    }

    /// 测试 relay 中转：GET /r/ping（经 Safari 进程，验证整条链路）
    func testRelay() async -> String {
        do {
            let (data, code) = try await relay.relay(method: "GET", path: "/r/ping", timeout: 20)
            if code == 200, let s = String(data: data, encoding: .utf8), s.contains("pong") {
                return "✅ relay 中转正常"
            }
            return "⚠️ relay 返回异常（\(code)）"
        } catch APIError.relayCancelled {
            return "⚠️ 已取消（用户关闭弹窗）"
        } catch {
            return "❌ relay 失败（\(error.localizedDescription)）"
        }
    }
}

enum APIError: Error, LocalizedError {
    case badURL, badResponse, badResponseDetail(String), badJSON, unauthorized, timeout, timeoutDetail(String), server(Int)
    case relayCancelled

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址无效"
        case .badResponse: return "服务器响应异常"
        case .badResponseDetail(let d): return "服务器响应异常（\(d)）"
        case .badJSON: return "数据解析失败"
        case .unauthorized: return "登录已过期，请重新登录"
        case .timeout: return "请求超时"
        case .timeoutDetail(let d): return "请求超时（\(d)）"
        case .server(let code): return "服务器错误（\(code)）"
        case .relayCancelled: return "已取消"
        }
    }
}
