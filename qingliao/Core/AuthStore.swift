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

    /// 可重试错误：连接丢失/超时/无法连接（蜂窝访问家庭宽带非标端口时常见瞬断）
    private func isRetryable(_ e: Error) -> Bool {
        if e is APIError { return false }   // 协议层错误不重试
        let code = (e as NSError).code
        return code == NSURLErrorNetworkConnectionLost || code == NSURLErrorTimedOut
            || code == NSURLErrorCannotConnectToHost || code == NSURLErrorNotConnectedToInternet
    }

    /// CFStream 统一请求入口（StreamHTTPClient 同步阻塞 → 后台线程 + continuation 包装，不阻塞 MainActor）
    private func streamRequest(_ path: String, method: String = "GET",
                               headers: [String: String] = [:], body: Data? = nil,
                               timeout: TimeInterval = 10) async throws -> (Data, Int) {
        var server = serverURL
        if !server.hasPrefix("http") { server = "http://" + server }
        guard let url = URL(string: server), let host = url.host else {
            throw APIError.badURL
        }
        let port = UInt16(url.port ?? (url.scheme == "https" ? 443 : 80))
        let isTLS = url.scheme == "https"
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                do {
                    let client = StreamHTTPClient()
                    let (data, code) = try client.request(
                        host: host, port: port, isTLS: isTLS,
                        method: method, path: path, headers: headers, body: body,
                        timeout: timeout
                    )
                    cont.resume(returning: (data, code))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
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

        let bodyData = (try? JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
            "remember": remember
        ])) ?? Data()

        // 瞬断自动重试（蜂窝网络常见瞬断，重试大概率建立新连接成功）
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, code) = try await streamRequest(
                    "/api/auth/login", method: "POST",
                    headers: ["Content-Type": "application/json"], body: bodyData
                )
                guard code == 200,
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

    func logout() {
        token = ""
        isLoggedIn = false
        defaults.removeObject(forKey: tokenKey)
    }

    /// 统一 API 请求：NWHTTPClient（HTTP/1.1 + SNI 域名 + 忽略证书 + 域名解析自动 IPv6）
    /// 注入 X-Auth-Token + 401 自动登出 + 瞬断自动重试
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        var server = serverURL
        if !server.hasPrefix("http") { server = "http://" + server }
        guard let url = URL(string: server + path) else {
            throw APIError.badURL
        }
        var headers: [String: String] = [:]
        if !token.isEmpty {
            headers["X-Auth-Token"] = token
        }
        let bodyData: Data?
        if let body {
            headers["Content-Type"] = "application/json"
            bodyData = try? JSONSerialization.data(withJSONObject: body)
        } else {
            bodyData = nil
        }
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, code) = try await streamRequest(
                    path, method: method,
                    headers: headers, body: bodyData
                )
                if code == 401 {
                    logout()
                    throw APIError.unauthorized
                }
                guard (200..<300).contains(code) else {
                    throw APIError.server(code)
                }
                let http = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
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
        guard let url = URL(string: s), let host = url.host else {
            return "❌ 服务器地址无效"
        }
        let port = UInt16(url.port ?? (url.scheme == "https" ? 443 : 80))
        let isTLS = url.scheme == "https"
        do {
            let (_, code) = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, Int), Error>) in
                DispatchQueue.global().async {
                    do {
                        let client = StreamHTTPClient()
                        let r = try client.request(
                            host: host, port: port, isTLS: isTLS,
                            method: "GET", path: "/api/auth/status",
                            headers: [:], body: nil, timeout: 8
                        )
                        cont.resume(returning: r)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            if code == 401 || code == 200 {
                return "✅ 连接正常（服务器已响应）"
            }
            return "⚠️ 服务器返回 \(code)"
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
        var headers: [String: String] = ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        if !token.isEmpty { headers["X-Auth-Token"] = token }

        let (data2, code) = try await streamRequest(
            path, method: "POST",
            headers: headers, body: body, timeout: 30
        )
        if code == 401 {
            logout()
            throw APIError.unauthorized
        }
        guard (200..<300).contains(code) else { throw APIError.server(code) }
        guard let json = try? JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
            throw APIError.badJSON
        }
        return json
    }
}

enum APIError: Error, LocalizedError {
    case badURL, badResponse, badResponseDetail(String), badJSON, unauthorized, timeout, timeoutDetail(String), server(Int)

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
        }
    }
}
