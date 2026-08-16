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

    /// v2.0.55：保存服务器地址（内存 + UserDefaults 持久化）
    func saveServer(_ s: String) {
        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
        serverURL = clean.isEmpty ? serverURL : clean
        defaults.set(serverURL, forKey: serverKey)
        // v2.0.71：多地址记忆（去重置顶，上限 8 条）
        if !clean.isEmpty {
            var list = serverHistory.filter { $0 != clean }
            list.insert(clean, at: 0)
            defaults.set(Array(list.prefix(8)), forKey: serversKey)
        }
    }

    // MARK: - v2.0.71 多地址记忆（登录页快速切换）

    private let serversKey = "qingliao_servers"

    var serverHistory: [String] {
        defaults.array(forKey: serversKey) as? [String] ?? []
    }

    func removeServer(_ s: String) {
        defaults.set(serverHistory.filter { $0 != s }, forKey: serversKey)
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
                // v2.0.102：登录前清空旧 token——换服务器登录时防残留旧服务器凭据
                if let t = j["token"] as? String, !t.isEmpty {
                    token = t
                } else {
                    token = ""
                }
                defaults.set(username, forKey: userKey)
                if !token.isEmpty { defaults.set(token, forKey: tokenKey) } else { defaults.removeObject(forKey: tokenKey) }
                isLoggedIn = true
                defaults.set(true, forKey: loggedKey)
                // v2.0.88：Face ID 登录开关开启（默认开）时保存凭据到 Keychain
                let faceIDOn = defaults.object(forKey: "qingliao_faceid_login") as? Bool ?? true
                if faceIDOn {
                    FaceIDStore.save(server: serverURL, username: username, password: password)
                }
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

    /// 统一 API 请求：网络分流
    /// - Wi-Fi/其他：URLSession 直连（免 relay 弹窗）
    /// - 蜂窝：CFStream 直连优先（纯 socket 绕 iOS 27 管控），失败降级 Safari relay
    /// 返回 (data, HTTPURLResponse)
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        let bodyData: Data?
        var headers: [String: String] = [:]
        if let body {
            headers["Content-Type"] = "application/json"
            bodyData = JSONSerialization.isValidJSONObject(body)
                ? (try? JSONSerialization.data(withJSONObject: body)) : nil
        } else {
            bodyData = nil
        }
        // v2.0.34 fix：登录后所有请求携带 X-Auth-Token。
        // 此前 token 只存不发 → auth 端点（change-password/logout/status）硬校验 token，
        // 无论 AUTO_LOGIN 与否都返回 401「未登录」→ 修改密码功能失效。
        if !token.isEmpty {
            headers["X-Auth-Token"] = token
        }

        // v2.0.70：蜂窝下恢复 relay 兜底（v2.0.68 一刀切去掉后蜂窝无法登录——iOS 管控下
        // 直连 POST 必挂，relay 是唯一通道；代价是 ASWAS 弹 Safari 授权窗，但可用优先）。
        // WiFi 下不弹：NetworkMonitor 已收紧（有 WiFi 接口绝不判蜂窝）+ 登录强制直连仅限 WiFi。
        let (data, code): (Data, Int)
        if NetworkMonitor.shared.isCellular {
            do {
                (data, code) = try await relay.directRequest(method: method, path: path,
                                                             headers: headers, body: bodyData, timeout: 10)
            } catch {
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

    /// 文件下载：Wi-Fi → URLSession 直连（二进制）；蜂窝 → Safari relay（带 query 直连挂，relay 可传小文件）
    /// v2.0.116 fix：带 X-Auth-Token（files_api 鉴权）
    func downloadFile(_ path: String) async throws -> (Data, Int) {
        if NetworkMonitor.shared.isCellular {
            return try await relay.relay(method: "GET", path: path,
                                         headers: ["X-Auth-Token": token], body: nil, timeout: 30)
        } else {
            return try await directHTTP(method: "GET", path: path,
                                        headers: ["X-Auth-Token": token], body: nil)
        }
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
            // 蜂窝：CFStream 直连上传（socket 层无 URL 4KB 限制，免弹窗），失败降级 relay（限 2KB 小文件）
            do {
                (respData, code) = try await relay.directRequest(
                    method: "POST", path: path,
                    headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                    body: body, timeout: 20
                )
            } catch {
                guard data.count < 2000 else {
                    throw APIError.badResponseDetail("文件过大（蜂窝下 relay 限 2KB，请用 PWA 上传）")
                }
                // v2.0.102：multipart body 含二进制（图片等）无法经 relay 文本通道——提前失败，不静默丢 body
                guard String(data: body, encoding: .utf8) != nil else {
                    throw APIError.badResponseDetail("二进制文件蜂窝下无法 relay 上传，请用 Wi-Fi")
                }
                (respData, code) = try await relay.relay(
                    method: "POST", path: path,
                    headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
                    body: body, timeout: 30
                )
            }
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
        // v2.0.98：Agent 开关（设置页 qingliao_agent_enabled，默认开；关闭后后端走普通 LLM 不调用工具）
        let agentOn = UserDefaults.standard.object(forKey: "qingliao_agent_enabled") as? Bool ?? true
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "model": model,
            "provider": provider,
            "messages": messages,
            "pushEnabled": false,
            "agentEnabled": agentOn
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        // v2.0.116 fix：流式请求必须带 X-Auth-Token（鉴权收紧后无 token 恒 401；
        // 原只带 Content-Type——AUTO_LOGIN 时代被免鉴权掩盖）
        let authHeaders = ["Content-Type": "application/json", "X-Auth-Token": token]
        let (data, code): (Data, Int)
        if NetworkMonitor.shared.isCellular {
            // 蜂窝：CFStream 直连 POST 标准端点（免弹窗），失败降级 relay 路径参数版
            do {
                (data, code) = try await relay.directRequest(
                    method: "POST", path: "/api/stream/start",
                    headers: authHeaders, body: bodyData, timeout: 25
                )
            } catch {
                let uid = RelayIdentity.uid(for: sessionId)
                (data, code) = try await relay.relay(
                    method: "POST", path: "/r/stream/start/\(uid)",
                    headers: authHeaders,
                    body: bodyData, timeout: 30
                )
            }
        } else {
            (data, code) = try await directHTTP(
                method: "POST", path: "/api/stream/start",
                headers: authHeaders, body: bodyData
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
    /// v2.0.96c：ASR 转写（raw 音频 body 上传 → 返回文字）
    /// v2.0.98b：Wi-Fi/蜂窝统一走 CFStream 直连 relay 路径（/r/asr/transcribe/）——
    ///           /api/asr 在部分服务器配置（443 IP 直连 307/无此路由）下失败，/r 路径稳定（nginx 16668/443 均已转发）
    func asrTranscribe(_ audioData: Data) async throws -> String {
        var headers: [String: String] = ["Content-Type": "application/octet-stream"]
        if !token.isEmpty {
            headers["X-Auth-Token"] = token
        }
        let uid = RelayIdentity.uid(for: currentStreamSessionId)
        let (data, code) = try await relay.directRequest(method: "POST", path: "/r/asr/transcribe/\\(uid)",
                                                         headers: headers, body: audioData, timeout: 90)
        guard (200..<300).contains(code),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        if let err = j["error"] as? String, !err.isEmpty, (j["ok"] as? Bool) != true {
            throw APIError.server(400)
        }
        return j["text"] as? String ?? ""
    }

    func streamPoll(taskId: String, offset: Int) async throws -> (String, Bool, String, String, Bool) {
        let (data, code): (Data, Int)
        // v2.0.116 fix：轮询也带 X-Auth-Token（后端 do_GET 统一鉴权）
        if NetworkMonitor.shared.isCellular {
            // 蜂窝：必须用路径参数形态（/r/stream/poll/... 无 query）——CFStream 带 query 会挂起 10s 超时，
            // 标准端点带 query 在蜂窝不可用（v2.0.5 实踩：流式输出失效）
            let uid = RelayIdentity.uid(for: currentStreamSessionId)
            (data, code) = try await relay.directGET(path: "/r/stream/poll/\(uid)/\(taskId)/\(offset)",
                                                     headers: ["X-Auth-Token": token], timeout: 10)
        } else {
            (data, code) = try await directHTTP(method: "GET", path: "/api/stream/\(taskId)?offset=\(offset)",
                                                headers: ["X-Auth-Token": token], body: nil)
        }
        guard (200..<300).contains(code),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse
        }
        let content = j["content"] as? String ?? ""
        let done = j["done"] as? Bool ?? false
        let status = j["status"] as? String ?? ""
        let error = j["error"] as? String ?? ""
        let agent = j["agent"] as? Bool ?? false   // v2.0.96b：Agent 回复标记
        return (content, done, status, error, agent)
    }

    /// 流式停止：蜂窝 → CFStream 直连 POST（免弹窗），失败降级 relay；Wi-Fi → 直连
    func streamStop(taskId: String) async {
        if NetworkMonitor.shared.isCellular {
            do {
                _ = try await relay.directRequest(method: "POST", path: "/api/stream/\(taskId)/stop",
                                                  headers: ["X-Auth-Token": token], timeout: 8)
            } catch {
                let uid = RelayIdentity.uid(for: currentStreamSessionId)
                _ = try? await relay.relay(method: "POST", path: "/r/stream/stop/\(uid)/\(taskId)",
                                           headers: ["X-Auth-Token": token], timeout: 10)
            }
        } else {
            _ = try? await directHTTP(method: "POST", path: "/api/stream/\(taskId)/stop",
                                      headers: ["X-Auth-Token": token], body: nil)
        }
    }

    /// 当前流式会话 id（StreamClient 启动时设置，用于 uid 推导）
    var currentStreamSessionId: String = ""

    // MARK: - 连通性测试

    /// 测试连接：v2.0.102 改为直连传入的地址（原实现测的是已保存地址，误导排查）
    func testConnection(server: String) async -> String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api/auth/status"), url.host != nil else {
            return "❌ 服务器地址无效"
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.httpMethod = "GET"
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 200 {
                return "✅ 连接正常（服务器已响应）"
            }
            return "⚠️ 服务器返回 \(code)"
        } catch {
            return "❌ 无法连接（\(error.localizedDescription)）"
        }
    }

    /// v2.0.87t：前台恢复自动重连（后台挂起蜂窝 IPv6 会话过期 → 恢复时重建连接）
    /// v2.0.87ar：蜂窝下只直连试探（不触发 relay 授权弹窗——弹窗只在用户实际操作时弹出）
    func refreshConnection() async {
        guard !serverURL.isEmpty else { return }
        do {
            if NetworkMonitor.shared.isCellular {
                _ = try await relay.directRequest(method: "GET", path: "/api/auth/status", timeout: 8)
            } else {
                _ = try await directHTTP(method: "GET", path: "/api/auth/status", headers: [:], body: nil)
            }
        } catch {
            // 静默：失败不打扰（避免频繁弹窗），用户实际操作时再走完整 relay
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
