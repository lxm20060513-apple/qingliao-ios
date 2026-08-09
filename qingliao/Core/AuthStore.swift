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
            let (data, resp) = try await URLSession.shared.data(for: req)
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
        } catch {
            errorMessage = "无法连接服务器（\(error.localizedDescription)）"
        }
    }

    func logout() {
        token = ""
        isLoggedIn = false
        defaults.removeObject(forKey: tokenKey)
    }

    /// 统一 API 请求：拼服务器地址 + 注入 X-Auth-Token + 401 自动登出
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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
