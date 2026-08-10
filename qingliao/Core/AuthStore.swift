import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    var isLoggedIn = false
    var username = ""
    var serverURL = ""
    var token = ""
    var errorMessage: String?
    var isLoading = false

    private let defaults = UserDefaults.standard
    private let serverKey = "qingliao_server"
    private let tokenKey = "qingliao_token"
    private let userKey = "qingliao_user"

    /// 自定义 ephemeral 会话：不复用连接池（规避 HTTP/2 连接复用导致的 -1005 Network connection lost）
    /// ⚠️ waitsForConnectivity 必须 false：连接挂起时若等待网络恢复会卡"登录中"长达 60s（实踩），快速失败交给重试循环
    private let certDelegate = CertIgnoreDelegate()
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: certDelegate, delegateQueue: nil)
    }()

    /// IPv6 直连模式（默认开）：服务器仅 IPv6 公网（域名 A 记录是运营商 NAT 无服务），URLSession happy-eyeballs 先连 IPv4 挂起等超时才试 IPv6 → 强制 IPv6 字面量直连跳过
    /// ⚠️ 勿做"IPv4 直连"：用户服务器无公网 IPv4，IPv4 是死路（实踩方向错误）
    var useIPv6Direct: Bool {
        get { defaults.object(forKey: "qingliao_ipv6_direct") == nil ? true : defaults.bool(forKey: "qingliao_ipv6_direct") }
        set { defaults.set(newValue, forKey: "qingliao_ipv6_direct") }
    }

    /// 域名解析取 IPv6 地址（getaddrinfo 强制 AF_INET6）
    private func resolveIPv6(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET6
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        var ip = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sa6 in
            inet_ntop(AF_INET6, &sa6.pointee.sin6_addr, &ip, socklen_t(INET6_ADDRSTRLEN))
        }
        return String(cString: ip)
    }

    /// 构造 URL：IPv6 直连模式下把域名换成 [IPv6] 字面量（配套忽略证书校验）
    private func buildURL(_ path: String) -> URL? {
        var server = serverURL
        if !server.hasPrefix("http") { server = "http://" + server }
        if useIPv6Direct, let host = URL(string: server)?.host, let ip = resolveIPv6(host) {
            server = server.replacingOccurrences(of: host, with: "[\(ip)]")
        }
        return URL(string: server + path)
    }

    /// 可重试错误：连接丢失/超时/无法连接（蜂窝访问家庭宽带非标端口时常见瞬断）
    private func isRetryable(_ e: Error) -> Bool {
        let code = (e as NSError).code
        return code == NSURLErrorNetworkConnectionLost || code == NSURLErrorTimedOut
            || code == NSURLErrorCannotConnectToHost || code == NSURLErrorNotConnectedToInternet
    }

    init() {
        token = defaults.string(forKey: tokenKey) ?? ""
        username = defaults.string(forKey: userKey) ?? ""
        serverURL = defaults.string(forKey: serverKey) ?? "http://192.168.0.40:8080"
        isLoggedIn = !token.isEmpty
    }

    /// 登录：签发 token 并存本地（记住登录 = UserDefaults 持久化）
    func login(username: String, password: String, remember: Bool = true) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        var server = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !server.hasPrefix("http") { server = "http://" + server }
        serverURL = server

        guard let url = buildURL("/api/auth/login") else {
            errorMessage = "服务器地址无效"
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
            "remember": remember
        ])
        do {
            // 瞬断自动重试（蜂窝网络常见 -1005，重试大概率建立新连接成功）
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    let (data, resp) = try await session.data(for: req)
                    guard let http = resp as? HTTPURLResponse else {
                        errorMessage = "网络异常"
                        return
                    }
                    guard http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let tok = json["token"] as? String else {
                        errorMessage = "用户名或密码错误"
                        return
                    }
                    token = tok
                    self.username = username
                    defaults.set(tok, forKey: tokenKey)
                    defaults.set(username, forKey: userKey)
                    defaults.set(serverURL, forKey: serverKey)
                    isLoggedIn = true
                    return
                } catch {
                    lastError = error
                    if attempt < 3, isRetryable(error) {
                        try? await Task.sleep(for: .seconds(Double(attempt)))
                        continue
                    }
                    break
                }
            }
            errorMessage = "无法连接服务器（\(lastError?.localizedDescription ?? "网络异常")）"
        }
    }

    func logout() {
        token = ""
        isLoggedIn = false
        defaults.removeObject(forKey: tokenKey)
    }

    /// 统一 API 请求：拼服务器地址 + 注入 X-Auth-Token + 401 自动登出 + 瞬断自动重试
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = buildURL(path) else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw APIError.badResponse
                }
                if http.statusCode == 401 {
                    logout()
                    throw APIError.unauthorized
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw APIError.server(http.statusCode)
                }
                return (data, http)
            } catch {
                lastError = error
                if attempt < 3, isRetryable(error) {
                    try? await Task.sleep(for: .seconds(Double(attempt)))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? APIError.badResponse
    }

    /// 便捷：JSON 请求 → 返回字典
    func json(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        let (data, _) = try await request(path, method: method, body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badJSON
        }
        return json
    }

    /// 连通性测试（登录页用）：GET /api/auth/status，401=服务器可达需鉴权（也算连接正常）
    func testConnection(server: String) async -> String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "http://" + s }
        if useIPv6Direct, let host = URL(string: s)?.host, let ip = resolveIPv6(host) {
            s = s.replacingOccurrences(of: host, with: "[\(ip)]")
        }
        guard let url = URL(string: s + "/api/auth/status") else { return "服务器地址无效" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return "网络响应异常" }
            if http.statusCode == 401 || http.statusCode == 200 {
                return "✅ 连接正常（服务器已响应）"
            }
            return "⚠️ 服务器返回 \(http.statusCode)"
        } catch {
            return "❌ 无法连接（\(error.localizedDescription)）"
        }
    }

    /// 便捷：JSON 请求 → 返回数组（如 /api/ha/states 返回实体数组）
    func jsonArray(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [Any] {
        let (data, _) = try await request(path, method: method, body: body)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw APIError.badJSON
        }
        return arr
    }

    /// multipart 文件上传（文件管理用，与 PWA FormData 同协议）
    func uploadMultipart(_ path: String, fileName: String, data: Data) async throws -> [String: Any] {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var server = serverURL
        if !server.hasPrefix("http") { server = "http://" + server }
        if useIPv6Direct, let host = URL(string: server)?.host, let ip = resolveIPv6(host) {
            server = server.replacingOccurrences(of: host, with: "[\(ip)]")
        }
        guard let url = URL(string: server + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue(token, forHTTPHeaderField: "X-Auth-Token") }
        req.httpBody = body
        let (data2, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        if http.statusCode == 401 {
            logout()
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
            throw APIError.badJSON
        }
        return json
    }
}

enum APIError: Error, LocalizedError {
    case badURL, badResponse, badJSON, unauthorized, server(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址无效"
        case .badResponse: return "服务器响应异常"
        case .badJSON: return "数据解析失败"
        case .unauthorized: return "登录已过期，请重新登录"
        case .server(let code): return "服务器错误（\(code)）"
        }
    }
}

/// 忽略证书校验的 delegate（IPv4 直连模式下 IP 与证书 CN 不匹配；自家服务可接受）
final class CertIgnoreDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
