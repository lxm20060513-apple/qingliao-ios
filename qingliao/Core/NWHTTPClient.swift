import Foundation
import Network

/// Network.framework 自建 HTTP/1.1 客户端
/// 背景：iOS URLSession 的 dataTask/uploadTask POST 在 IPv6 + HTTP/2 下挂起超时（GET 正常，实测多轮无解）；
///       用 NWConnection 手动控制：HTTP/1.1（无 h2）、SNI=域名、忽略证书校验、域名解析自动走 IPv6（A 记录已删）。
final class NWHTTPClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "qingliao.nwhttp")

    func request(serverURL: String, path: String, method: String = "GET",
                 headers: [String: String] = [:], body: Data? = nil,
                 timeout: TimeInterval = 10) async throws -> (Data, Int) {
        var s = serverURL
        if !s.hasPrefix("http") { s = "http://" + s }
        guard let url = URL(string: s), let host = url.host else {
            throw APIError.badURL
        }
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? (url.scheme == "https" ? 443 : 80)))!
        let isTLS = url.scheme == "https"

        // TLS 参数：SNI=域名 + 忽略证书（自家服务）
        let params: NWParameters
        if isTLS {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, completion in
                completion(true)
            }, queue)
            sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, false)
            params = NWParameters(tls: tls)
        } else {
            params = NWParameters()
        }

        // 构造 HTTP/1.1 请求
        var requestHead = "\(method) \(path) HTTP/1.1\r\n"
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host
        requestHead += "Host: \(hostHeader)\r\n"
        for (k, v) in headers { requestHead += "\(k): \(v)\r\n" }
        if let body {
            requestHead += "Content-Length: \(body.count)\r\n"
        }
        requestHead += "Connection: close\r\n\r\n"
        var payload = Data(requestHead.utf8)
        if let body { payload.append(body) }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Int), Error>) in
            let connection = NWConnection(
                to: .hostPort(host: .init(host), port: port),
                using: params
            )
            let session = NWRequestSession(connection: connection, continuation: continuation, queue: queue)
            session.start(payload: payload)

            // 超时兜底
            let timer = DispatchWorkItem { [weak session] in
                session?.timeout()
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
    }

    /// 解析 HTTP 响应：状态行 + 头 + body（Connection: close 语义，数据完整到达后解析）
    static func parseResponse(_ data: Data) -> (Data, Int) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return (data, 0)
        }
        let headerPart = data[..<headerEnd.lowerBound]
        let bodyPart = data[headerEnd.upperBound...]
        let headerText = String(data: headerPart, encoding: .utf8) ?? ""
        var code = 0
        if let firstLine = headerText.split(separator: "\r\n").first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2 {
                code = Int(parts[1]) ?? 0
            }
        }
        return (Data(bodyPart), code)
    }
}

/// 单次请求会话协调器（@unchecked Sendable：所有状态在内部 serial queue 上访问，闭包只捕获 self）
final class NWRequestSession: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<(Data, Int), Error>
    private let queue: DispatchQueue
    private var buffer = Data()
    private var finished = false
    /// self-retain：请求期间强引用自己（continuation 闭包不持有 session，无强引用会被 ARC 释放 → 所有 weak 回调失效 + 超时 timer 失效 = 永久挂起）
    private var retainedSelf: NWRequestSession?

    init(connection: NWConnection,
         continuation: CheckedContinuation<(Data, Int), Error>,
         queue: DispatchQueue) {
        self.connection = connection
        self.continuation = continuation
        self.queue = queue
    }

    func start(payload: Data) {
        retainedSelf = self
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.connection.send(content: payload, completion: .contentProcessed { [weak self] error in
                    if let error = error {
                        self?.finish(.failure(error))
                    } else {
                        self?.receiveLoop()
                    }
                })
            case .failed(let error):
                self?.finish(.failure(error))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func timeout() {
        finish(.failure(APIError.timeout))
    }

    private func receiveLoop() {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                self.finish(.failure(error))
                return
            }
            if let data {
                self.buffer.append(data)
            }
            if isComplete {
                self.finish(.success(NWHTTPClient.parseResponse(self.buffer)))
            } else {
                self.receiveLoop()
            }
        }
    }

    private func finish(_ result: Result<(Data, Int), Error>) {
        guard !finished else { return }
        finished = true
        retainedSelf = nil
        connection.cancel()
        continuation.resume(with: result)
    }
}
