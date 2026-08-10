import Foundation

/// CFNetwork Stream 层 HTTP/1.1 客户端（iOS 最古老稳定的网络路径）
/// 背景：URLSession(dataTask/uploadTask) 与 NWConnection 在 iOS 27 + 蜂窝 + IPv6 + HTTPS POST 下均失败（挂起/EINVAL）；
///       CFStream(NSStream) 是 CFNetwork 底层流 API，Apple 承诺向后兼容，绕开上述两个栈。
/// 特性：HTTP/1.1、TLS 手动控制（SNI=域名 + 忽略证书校验）、域名解析走系统（A 记录已删→IPv6）。
/// 超时：iOS 无 CFStream 读超时属性 → watchdog 线程到点强制关闭流中断阻塞读。
final class StreamHTTPClient: @unchecked Sendable {

    /// 同步执行一次 HTTP 请求（在调用线程阻塞，配合全局队列/await 包装）
    /// - Returns: (响应 body, HTTP 状态码)
    func request(host: String, port: UInt16, isTLS: Bool,
                 method: String, path: String,
                 headers: [String: String], body: Data?,
                 timeout: TimeInterval) throws -> (Data, Int) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        guard let read = readStream?.takeRetainedValue(),
              let write = writeStream?.takeRetainedValue() else {
            throw APIError.badResponse
        }
        defer {
            CFReadStreamClose(read)
            CFWriteStreamClose(write)
        }

        if isTLS {
            // TLS 设置：SNI=域名（kCFStreamSSLPeerName）+ 忽略证书链校验（自家服务；证书本身是有效 Let's Encrypt）
            let settings: [CFString: Any] = [
                kCFStreamSSLLevel: kCFStreamSocketSecurityLevelNegotiatedSSL,
                kCFStreamSSLPeerName: host,
                kCFStreamSSLValidatesCertificateChain: kCFBooleanFalse,
                kCFStreamSSLAllowsExpiredCertificates: kCFBooleanTrue,
                kCFStreamSSLAllowsAnyRoot: kCFBooleanTrue,
            ]
            CFReadStreamSetProperty(read, kCFStreamPropertySSLSettings, settings as CFDictionary)
            CFWriteStreamSetProperty(write, kCFStreamPropertySSLSettings, settings as CFDictionary)
        }

        // 超时 watchdog：到点强制关闭流 → 中断阻塞的读写
        let watchdog = DispatchWorkItem {
            CFReadStreamClose(read)
            CFWriteStreamClose(write)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        guard CFReadStreamOpen(read), CFWriteStreamOpen(write) else {
            watchdog.cancel()
            throw APIError.badResponse
        }

        // 构造 HTTP/1.1 请求
        var requestText = "\(method) \(path) HTTP/1.1\r\n"
        requestText += "Host: \(host):\(port)\r\n"
        for (k, v) in headers {
            requestText += "\(k): \(v)\r\n"
        }
        if let body {
            requestText += "Content-Length: \(body.count)\r\n"
        }
        requestText += "Connection: close\r\n\r\n"
        var payload = Data(requestText.utf8)
        if let body {
            payload.append(body)
        }

        // 写入（TLS 握手在此触发）
        let written = payload.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> CFIndex in
            CFWriteStreamWrite(write, buf.baseAddress!.assumingMemoryBound(to: UInt8.self), buf.count)
        }
        if written < 0 {
            watchdog.cancel()
            throw APIError.badResponse
        }

        // 读取响应（同步阻塞，超时由 watchdog 强制关闭中断）
        var resp = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while true {
            let n = CFReadStreamRead(read, buffer, 4096)
            if n < 0 {
                // 被 watchdog 关闭 = 超时；或服务器 RST——已有数据则按 EOF 处理（lucky 发完响应立即 RST 实测）
                if watchdog.isCancelled { break }          // 正常完成路径（watchdog 已 cancel）
                if resp.isEmpty {
                    watchdog.cancel()
                    throw APIError.timeout
                }
                break
            }
            if n == 0 { break }  // EOF
            resp.append(buffer, count: n)
        }
        watchdog.cancel()

        return Self.parseResponse(resp)
    }

    /// 解析 HTTP 响应：状态行 + 头 + body
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
