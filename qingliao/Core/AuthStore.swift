import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    var isLoggedIn = false          // 登录状态（UserDefaults 持久化）
    var username = ""
    var serverURL = ""
    var token = ""
    var errorMessage: String?
    var isLoading = false

    private let defaults = UserDefaults.standard
    private let serverKey = "qingliao_server"
    private let tokenKey = "qingliao_token"
    private let userKey = "qingliao_user"
    private let loggedKey = "qingliao_logged_in"

    /// Safari Relay 网络层（iOS 27 蜂窝上行挂起的最终方案）
    private let relay = SafariRelay.shared
    /// Wi-Fi 直连会话（蜂窝外使用，免 relay 弹窗）
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false   // 快速失败交给重试循环
        session = URLSession(configuration: cfg)
        token = defaults.string(forKey: tokenKey) ?? ""
        username = defaults.string(forKey: userKey) ?? ""
        serverURL = defaults.string(forKey: serverKey) ?? "https://example.com:16666"
        isLoggedIn = defaults.bool(forKey: loggedKey)
    }

    // MARK: - 登录（POST /api/auth/login 验证账号密码；服务器 AUTO_LOGIN 免鉴权，登录页作为门禁）

    func login(username: String, password: String, remember: Bool = true) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (data, resp) = try await request("/api/auth/login", method: "POST", body: [
                "username": username, "password": password, "remember": remember
            ])
            _ = resp.statusCode
            // request() 会把 401 透传成 200；这里必须校验 body 的 ok 字段
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (j["ok"] as? Bool) == true {
                self.username = username
                if let t = j["token"] as? String, !t.isEmpty { token = t }
                defaults.set(username, forKey: userKey)
                if !token.isEmpty { defaults.set(token, forKey: tokenKey) }
                isLoggedIn = true
                defaults.set(true, forKey: loggedKey)
            } else {
                errorMessage = "用户名或密码错误"
            }
        } catch {
            errorMessage = "无法连接服务器（\(error.localizedDescription)）"
        }
    }

    func logout() {
        token = ""
        isLoggedIn = false
        defaults.set(false, forKey: loggedKey)
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
        if NetworkMonitor.shared.isCellular {
            // 蜂窝：iOS 27 管控 → 无参 GET 走 CFStream 直连，其余走 Safari relay（弹窗不可避免）
            if canDirect {
                (data, code) = try await relay.directGET(path: path, headers: headers, timeout: 10)
            } else {
                (data, code) = try await relay.relay(method: method, path: path,
                                                     headers: headers, body: bodyData,
                                                     timeout: 30)
            }
        } else {
            // Wi-Fi/其他：URLSession 直连（免 relay 弹窗）
            (data, code) = try await directHTTP(method: method, path: path, headers: headers, body: bodyData)
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

    /// Wi-Fi 直连：URLSession（ephemeral，瞬断重试 3 次）——蜂窝外免 relay 弹窗
    private func directHTTP(method: String, path: String, headers: [String: String], body: Data?) async throws -> (Data, Int) {
        guard let url = URL(string: serverURL + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = body }
        var lastErr: Error?
        for attempt in 0..<3 {
            do {
                let (d, r) = try await session.data(for: req)
                let code = (r as? HTTPURLResponse)?.statusCode ?? 0
                return (d, code)
            } catch {
                lastErr = error
                let ns = error as NSError
                // 瞬断类错误（连接丢失/超时/断网）重试；其余直接抛
                if attempt < 2, [-1005, -1001, -1009, -1021].contains(ns.code) {
                    try? await Task.sleep(for: .seconds(Double(attempt + 1)))
                    continue
                }
                throw error
            }
        }
        throw lastErr ?? APIError.badResponse
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

    /// multipart 文件上传：Wi-Fi → URLSession 直传（无大小限制）；蜂窝 → relay 中转（限 2KB 小文件）
    func uploadMultipart(_ path: String, fileName: String, data: Data) async throws -> [String: Any] {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (respData, code): (Data, Int)
        if NetworkMonitor.shared.isCellular {
            // 大文件 relay 传不下（URL 4KB 限制）→ 限制 2KB 以下小文件
            guard data.count < 2000 else {
                throw APIError.badResponseDetail("文件过大（蜂窝下 relay 限 2KB，请用 PWA 上传）")
            }
            (respData, code) = try await relay.relay(
                method: "POST", path: path,
                headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                body: body, timeout: 30
            )
        } else {
            (respData, code) = try await directHTTP(
                method: "POST", path: path,
                headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                body: body
            )
        }
        guard (200..<300).contains(code) else { throw APIError.server(code) }
        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            throw APIError.badJSON
        }
        return json
    }

    // MARK: - 流式专用（relay 路径参数版）

    /// 流式启动：蜂窝 → relay POST /r/stream/start/{uid}；Wi-Fi → 直连 POST /api/stream/start
    func streamStart(sessionId: String, model: String, provider: String,
                     messages: [[String: Any]]) async throws -> String {
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "model": model,
            "provider": provider,
            "messages": messages,
            "pushEnabled": false
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let (data, code): (Data, Int)
        if NetworkMonitor.shared.isCellular {
            let uid = RelayIdentity.uid(for: sessionId)
            (data, code) = try await relay.relay(
                method: "POST", path: "/r/stream/start/\(uid)",
                headers: ["Content-Type": "application/json"],
                body: bodyData, timeout: 30
            )
        } else {
            (data, code) = try await directHTTP(
                method: "POST", path: "/api/stream/start",
                headers: ["Content-Type": "application/json"], body: bodyData
            )
        }
        guard (200..<300).contains(code),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tid = json["taskId"] as? String else {
            throw APIError.badResponseDetail("stream start fail (\(code))")
        }
        return tid
    }

    /// 流式轮询：蜂窝 → 直连 GET /r/stream/poll/{uid}/{taskId}/{offset}（路径参数）；Wi-Fi → 直连 GET /api/stream/{taskId}?offset=N
    func streamPoll(taskId: String, offset: Int) async throws -> (String, Bool, String, String) {
        let (data, code): (Data, Int)
        if NetworkMonitor.shared.isCellular {
            let uid = RelayIdentity.uid(for: currentStreamSessionId)
            (data, code) = try await relay.directGET(path: "/r/stream/poll/\(uid)/\(taskId)/\(offset)", timeout: 10)
        } else {
            (data, code) = try await directHTTP(method: "GET", path: "/api/stream/\(taskId)?offset=\(offset)",
                                                headers: [:], body: nil)
        }
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

    /// 流式停止：蜂窝 → relay POST /r/stream/stop/{uid}/{taskId}；Wi-Fi → 直连 POST /api/stream/{taskId}/stop
    func streamStop(taskId: String) async {
        if NetworkMonitor.shared.isCellular {
            let uid = RelayIdentity.uid(for: currentStreamSessionId)
            _ = try? await relay.relay(method: "POST", path: "/r/stream/stop/\(uid)/\(taskId)", timeout: 10)
        } else {
            _ = try? await directHTTP(method: "POST", path: "/api/stream/\(taskId)/stop", headers: [:], body: nil)
        }
    }

    /// 当前流式会话 id（StreamClient 启动时设置，用于 uid 推导）
    var currentStreamSessionId: String = ""

    // MARK: - 连通性测试

    /// 测试连接：Wi-Fi → URLSession 直连；蜂窝 → CFStream 直连 GET（无参，iOS 27 唯一确定通的形态）
    func testConnection(server: String) async -> String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else {
            return "❌ 服务器地址无效"
        }
        do {
            let (_, code): (Data, Int)
            if NetworkMonitor.shared.isCellular {
                (_, code) = try await relay.directGET(path: "/api/auth/status", timeout: 8)
            } else {
                (_, code) = try await directHTTP(method: "GET", path: "/api/auth/status", headers: [:], body: nil)
            }
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
