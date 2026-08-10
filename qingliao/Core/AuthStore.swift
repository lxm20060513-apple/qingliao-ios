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
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

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

        guard let url = URL(string: server + "/api/auth/login") else {
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
        var server = serverURL
        if !server.hasPrefix("http") { server = "http://" + server }
        guard let url = URL(string: server + path) else {
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
