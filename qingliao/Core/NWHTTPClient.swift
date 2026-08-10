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
            var finished = false
            let connection = NWConnection(
                to: .hostPort(host: .init(host), port: port),
                using: params
            )

            func finish(_ result: Result<(Data, Int), Error>) {
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(with: result)
            }

            var buffer = Data()

            func receiveLoop() {
                connection.receiveMessage { data, _, isComplete, error in
                    if let error = error {
                        finish(.failure(error))
                        return
                    }
                    if let data {
                        buffer.append(data)
                    }
                    if isComplete {
                        let parsed = NWHTTPClient.parseResponse(buffer)
                        finish(.success(parsed))
                    } else {
                        receiveLoop()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error = error {
                            finish(.failure(error))
                        } else {
                            receiveLoop()
                        }
                    })
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // 超时兜底
            let timer = DispatchWorkItem { [weak connection] in
                if !finished {
                    connection?.cancel()
                    finish(.failure(APIError.timeout))
                }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
    }

    /// 解析 HTTP 响应：状态行 + 头 + body（Connection: close 语义，数据完整到达后解析）
    private static func parseResponse(_ data: Data) -> (Data, Int) {
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
