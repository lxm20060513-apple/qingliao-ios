import Foundation

/// CFNetwork Stream 层 HTTP/1.1 客户端（iOS 最古老稳定的网络路径）
/// 背景：URLSession(dataTask/uploadTask) 与 NWConnection 在 iOS 27 + 蜂窝 + IPv6 + HTTPS POST 下均失败（挂起/EINVAL）；
///       CFStream 是 CFNetwork 底层流 API，绕开上述两个栈。
/// ⚠️ 读取必须事件驱动（runloop + kCFStreamEventHasBytesAvailable）：lucky 响应大拆多段、发完 RST/keep-alive 不关连接，
///     阻塞式 CFReadStreamRead 等 EOF 会永远卡住（跨线程 close 也中断不了阻塞读——实踩"登录中"卡死）。
///     完成判定 = 按响应头 Content-Length 收满即停（Safari/curl 同款逻辑，kimi-k3 确认的根因）。
final class StreamHTTPClient: @unchecked Sendable {

    /// 同步执行一次 HTTP 请求（阻塞当前线程直到完成/超时；由调用方放到后台线程）
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
            CFReadStreamUnscheduleFromRunLoop(read, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode)
            CFReadStreamClose(read)
            CFWriteStreamClose(write)
        }

        if isTLS {
            // TLS：SNI=域名（kCFStreamSSLPeerName）+ 忽略证书链校验（自家服务）
            let settings: [CFString: Any] = [
                kCFStreamSSLLevel: kCFStreamSocketSecurityLevelNegotiatedSSL,
                kCFStreamSSLPeerName: host as CFString,
                kCFStreamSSLValidatesCertificateChain: kCFBooleanFalse,
            ]
            let sslKey = CFStreamPropertyKey(kCFStreamPropertySSLSettings)
            CFReadStreamSetProperty(read, sslKey, settings as CFDictionary)
            CFWriteStreamSetProperty(write, sslKey, settings as CFDictionary)
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

        // 状态对象（C 回调 context.info 传递）
        let state = StreamState(payload: payload)
        var context = CFStreamClientContext(
            version: 0,
            info: Unmanaged.passUnretained(state).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        // kCFStreamEvent* 在 Swift 中不可见，用原始值：Open=1 HasBytes=2 CanAccept=4 Error=8 End=16
        let events = CFOptionFlags(1) | CFOptionFlags(2) | CFOptionFlags(4) | CFOptionFlags(8) | CFOptionFlags(16)
        CFReadStreamSetClient(read, events, { _, event, info in
            guard let info else { return }
            let s = Unmanaged<StreamState>.fromOpaque(info).takeUnretainedValue()
            StreamHTTPClient.handleReadEvent(event, state: s, read: nil)
        }, &context)
        CFWriteStreamSetClient(write, events, { _, event, info in
            guard let info else { return }
            let s = Unmanaged<StreamState>.fromOpaque(info).takeUnretainedValue()
            StreamHTTPClient.handleWriteEvent(event, state: s, write: nil)
        }, &context)

        // 状态对象持有流引用（回调里用）
        state.read = read
        state.write = write

        let runLoop = CFRunLoopGetCurrent()
        CFReadStreamScheduleWithRunLoop(read, runLoop, CFRunLoopMode.defaultMode)
        CFWriteStreamScheduleWithRunLoop(write, runLoop, CFRunLoopMode.defaultMode)

        // 超时：到点强制 stop runloop（事件驱动无阻塞读，可安全中断）
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + timeout, 0, 0, 0) { _ in
            state.timeout = true
            state.done = true
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopAddTimer(runLoop, timer, CFRunLoopMode.defaultMode)

        CFReadStreamOpen(read)
        CFWriteStreamOpen(write)
        CFRunLoopRun()   // 阻塞直到 stop（完成/超时/错误）

        CFRunLoopRemoveTimer(runLoop, timer, CFRunLoopMode.defaultMode)

        if state.timeout {
            throw APIError.timeout
        }
        if let error = state.error {
            throw error
        }
        guard let result = state.result else {
            throw APIError.badResponse
        }
        return result
    }

    /// read 流事件
    private static func handleReadEvent(_ event: CFStreamEventType, state: StreamState, read: CFReadStream?) {
        guard let read = state.read else { return }
        switch event {
        case CFStreamEventType(rawValue: 1):   // OpenCompleted：TLS 握手完成 → 发送请求
            sendPayload(state)
        case CFStreamEventType(rawValue: 2):   // HasBytesAvailable
            var buf = [UInt8](repeating: 0, count: 8192)
            while CFReadStreamHasBytesAvailable(read) {
                let n = CFReadStreamRead(read, &buf, buf.count)
                if n <= 0 { break }
                state.buffer.append(buf, count: n)
            }
            if StreamHTTPClient.isResponseComplete(state.buffer) {
                state.result = StreamHTTPClient.parseResponse(state.buffer)
                state.done = true
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        case CFStreamEventType(rawValue: 16):  // EndEncountered（EOF）
            // EOF（服务器关闭连接）：有数据则按当前缓冲解析
            if !state.buffer.isEmpty, state.result == nil {
                state.result = StreamHTTPClient.parseResponse(state.buffer)
            }
            state.done = true
            CFRunLoopStop(CFRunLoopGetCurrent())
        case CFStreamEventType(rawValue: 8):   // ErrorOccurred（可能 RST）
            // 错误（可能 RST）：已有缓冲且能解析出状态码 → 按成功处理（lucky 发完响应立即 RST 实测）
            if !state.buffer.isEmpty, state.result == nil {
                let (body, code) = StreamHTTPClient.parseResponse(state.buffer)
                if code > 0 {
                    state.result = (body, code)
                    state.done = true
                    CFRunLoopStop(CFRunLoopGetCurrent())
                    return
                }
            }
            state.error = APIError.badResponse
            state.done = true
            CFRunLoopStop(CFRunLoopGetCurrent())
        default:
            break
        }
    }

    /// write 流事件（CanAcceptBytes → 发送请求）
    private static func handleWriteEvent(_ event: CFStreamEventType, state: StreamState, write: CFWriteStream?) {
        switch event {
        case CFStreamEventType(rawValue: 1):   // OpenCompleted
            sendPayload(state)
        case CFStreamEventType(rawValue: 4):   // CanAcceptBytes
            sendPayload(state)
        default:
            break
        }
    }

    private static func sendPayload(_ state: StreamState) {
        guard !state.sent, let write = state.write, let payload = state.payload else { return }
        var remaining = payload
        while !remaining.isEmpty {
            let n = remaining.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> CFIndex in
                CFWriteStreamWrite(write, buf.baseAddress!.assumingMemoryBound(to: UInt8.self), buf.count)
            }
            if n < 0 {
                if !state.buffer.isEmpty {
                    let (body, code) = StreamHTTPClient.parseResponse(state.buffer)
                    if code > 0 { state.result = (body, code) }
                }
                state.done = true
                CFRunLoopStop(CFRunLoopGetCurrent())
                return
            }
            if n == 0 { return }   // 缓冲满，等 CanAcceptBytes 再发
            remaining.removeFirst(n)
        }
        state.sent = true
    }

    /// 按 Content-Length 判断响应是否完整（kimi-k3 确认的根因修复：Safari/curl 同款判定）
    private static func isResponseComplete(_ buffer: Data) -> Bool {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        for line in headerText.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:"),
               let lenStr = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
               let len = Int(lenStr) {
                let bodyLen = buffer.count - headerEnd.upperBound
                return bodyLen >= len
            }
        }
        return false
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

/// 单次请求状态（C 回调 context.info 传递，runloop 单线程访问）
final class StreamState: @unchecked Sendable {
    var payload: Data?
    var read: CFReadStream?
    var write: CFWriteStream?
    var buffer = Data()
    var sent = false
    var done = false
    var timeout = false
    var error: Error?
    var result: (Data, Int)?

    init(payload: Data?) {
        self.payload = payload
    }
}
