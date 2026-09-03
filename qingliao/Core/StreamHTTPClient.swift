import Foundation

/// CFNetwork Stream 层 HTTP/1.1 客户端（iOS 最古老稳定的网络路径）
/// 背景：URLSession(dataTask/uploadTask) 与 NWConnection 在 iOS 27 + 蜂窝 + IPv6 + HTTPS POST 下均失败（挂起/EINVAL）；
///       CFStream 是 CFNetwork 底层流 API，绕开上述两个栈。
/// ⚠️ 读取必须事件驱动（runloop + kCFStreamEventHasBytesAvailable）：lucky 响应大拆多段、发完 RST/keep-alive 不关连接，
///     阻塞式 CFReadStreamRead 等 EOF 会永远卡住（跨线程 close 也中断不了阻塞读——实踩"登录中"卡死）。
///     完成判定 = 按响应头 Content-Length 收满即停（Safari/curl 同款逻辑，kimi-k3 确认的根因）。
final class StreamHTTPClient: @unchecked Sendable {

    /// 同步执行一次 HTTP 请求（阻塞当前线程直到完成/超时；由调用方放到后台线程）。
    /// ⚠️ 必须在后台线程调用——在主线程调用会卡死 UI（runloop 等待响应）。
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
            // TLS：SNI=域名（kCFStreamSSLPeerName）；仅本地服务跳过证书链校验，外部服务正常验证
            var settings: [CFString: Any] = [
                kCFStreamSSLLevel: kCFStreamSocketSecurityLevelNegotiatedSSL,
                kCFStreamSSLPeerName: host as CFString,
            ]
            let isLocal = (host == "127.0.0.1" || host == "localhost" || host == "::1")
            if isLocal {
                settings[kCFStreamSSLValidatesCertificateChain] = kCFBooleanFalse
            }
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
            s.lastEvent = Int(event.rawValue)
            StreamHTTPClient.handleReadEvent(event, state: s, read: nil)
        }, &context)
        CFWriteStreamSetClient(write, events, { _, event, info in
            guard let info else { return }
            let s = Unmanaged<StreamState>.fromOpaque(info).takeUnretainedValue()
            s.lastEvent = Int(event.rawValue)
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
            throw APIError.timeoutDetail("buf=\(state.buffer.count) sent=\(state.sent) ev=\(state.lastEvent) wf=\(state.writeFailCount)")
        }
        if let error = state.error {
            throw error
        }
        guard let result = state.result else {
            throw APIError.badResponseDetail("noresult buf=\(state.buffer.count) ev=\(state.lastEvent) sent=\(state.sent)")
        }
        return result
    }

    /// read 流事件
    private static func handleReadEvent(_ event: CFStreamEventType, state: StreamState, read: CFReadStream?) {
        guard let read = state.read else { return }
        switch event {
        case CFStreamEventType(rawValue: 1):   // OpenCompleted：仅 TCP 连接完成，TLS 未就绪 → 不发送
            break
        case CFStreamEventType(rawValue: 2):   // HasBytesAvailable
            var buf = [UInt8](repeating: 0, count: 8192)
            while CFReadStreamHasBytesAvailable(read) {
                let n = CFReadStreamRead(read, &buf, buf.count)
                if n <= 0 { break }
                state.appendToBuffer(Data(buf[0..<n]))
            }
            // 原子检查：buffer 读取 + Content-Length 判定 + result/done 设置在同一锁内
            if state.tryFinalizeOnComplete() {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        case CFStreamEventType(rawValue: 16):  // EndEncountered（EOF）
            // EOF（服务器关闭连接）：原子操作——有数据则按当前缓冲解析，设置 done
            if state.handleEOF() {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        case CFStreamEventType(rawValue: 8):   // ErrorOccurred（可能 RST）
            // 错误（可能 RST）：原子操作——已有缓冲且能解析出状态码 → 按成功处理
            let err = APIError.badResponseDetail("err buf=\(state.buffer.count) ev=\(state.lastEvent)")
            if state.handleError(err) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        default:
            break
        }
    }

    /// write 流事件（CanAcceptBytes → 发送请求）
    private static func handleWriteEvent(_ event: CFStreamEventType, state: StreamState, write: CFWriteStream?) {
        switch event {
        case CFStreamEventType(rawValue: 1):   // OpenCompleted：仅 TCP 连接完成，TLS 未就绪 → 不发送
            break
        case CFStreamEventType(rawValue: 4):   // CanAcceptBytes：TLS 握手完成后才可写 → 发送请求
            sendPayload(state)
        default:
            break
        }
    }

    private static func sendPayload(_ state: StreamState) {
        guard let (write, payload, startOffset) = state.beginSend() else { return }
        defer { state.endSend() }
        // 从上次发送偏移续传（write 返回 0 缓冲满时不能从开头重发——会重复发送导致服务器解析错乱）
        var offset = startOffset
        while offset < payload.count {
            let remaining = payload[offset...]
            let n = remaining.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> CFIndex in
                CFWriteStreamWrite(write, buf.baseAddress!.assumingMemoryBound(to: UInt8.self), buf.count)
            }
            if n < 0 {
                // write 失败：TLS 握手可能尚未就绪 → 延迟重试（CanAcceptBytes 只触发一次，不能等事件）
                let result = state.recordWriteFailure()
                if result.abort {
                    CFRunLoopStop(CFRunLoopGetCurrent())
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + result.retryDelay) {
                        sendPayload(state)
                    }
                }
                return
            }
            if n == 0 {
                // 缓冲满：CanAcceptBytes 只触发一次不再来 → 延迟重试续传（30 次 ~3s 上限）
                if state.recordZeroWrite() {
                    CFRunLoopStop(CFRunLoopGetCurrent())
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { sendPayload(state) }
                }
                return
            }
            state.advanceOffset(by: n)
            offset += n
        }
        state.markSent()
    }

    /// 按 Content-Length 判断响应是否完整（kimi-k3 确认的根因修复：Safari/curl 同款判定）
    fileprivate static func isResponseComplete(_ buffer: Data) -> Bool {
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

/// 单次请求状态（C 回调 context.info 传递；runloop + DispatchQueue 并发访问，用锁保护）
final class StreamState: @unchecked Sendable {
    private let lock = NSLock()

    // 以下字段全部在锁保护下访问
    private var _payload: Data?
    private var _read: CFReadStream?
    private var _write: CFWriteStream?
    private var _buffer = Data()
    private var _sent = false
    private var _sentOffset = 0
    private var _writeFailCount = 0
    private var _zeroWrites = 0
    private var _inFlight = false          // sendPayload 并发守卫
    private var _lastEvent: Int = -1
    private var _done = false
    private var _timeout = false
    private var _error: Error?
    private var _result: (Data, Int)?

    // MARK: - 线程安全访问器

    var payload: Data? {
        get { lock.withLock { _payload } }
        set { lock.withLock { _payload = newValue } }
    }

    var read: CFReadStream? {
        get { lock.withLock { _read } }
        set { lock.withLock { _read = newValue } }
    }

    var write: CFWriteStream? {
        get { lock.withLock { _write } }
        set { lock.withLock { _write = newValue } }
    }

    var buffer: Data {
        get { lock.withLock { _buffer } }
        set { lock.withLock { _buffer = newValue } }
    }

    /// 仅追加 buffer（避免整个 getter/setter 之间的竞态）
    func appendToBuffer(_ data: Data) {
        lock.withLock { _buffer.append(data) }
    }

    var sent: Bool {
        get { lock.withLock { _sent } }
        set { lock.withLock { _sent = newValue } }
    }

    var sentOffset: Int {
        get { lock.withLock { _sentOffset } }
        set { lock.withLock { _sentOffset = newValue } }
    }

    var writeFailCount: Int {
        get { lock.withLock { _writeFailCount } }
        set { lock.withLock { _writeFailCount = newValue } }
    }

    var zeroWrites: Int {
        get { lock.withLock { _zeroWrites } }
        set { lock.withLock { _zeroWrites = newValue } }
    }

    var lastEvent: Int {
        get { lock.withLock { _lastEvent } }
        set { lock.withLock { _lastEvent = newValue } }
    }

    var done: Bool {
        get { lock.withLock { _done } }
        set { lock.withLock { _done = newValue } }
    }

    var timeout: Bool {
        get { lock.withLock { _timeout } }
        set { lock.withLock { _timeout = newValue } }
    }

    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    var result: (Data, Int)? {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    // MARK: - Atomic compound operations (check-then-act)

    /// Atomically begin sending: guards done/sent/inFlight, returns payload info.
    /// Caller MUST call endSend() when done.
    func beginSend() -> (write: CFWriteStream, payload: Data, offset: Int)? {
        lock.withLock {
            guard !_done, !_sent, !_inFlight, let w = _write, let p = _payload else { return nil }
            _inFlight = true
            return (w, p, _sentOffset)
        }
    }

    /// Mark send attempt complete (clear inFlight).
    func endSend() {
        lock.withLock { _inFlight = false }
    }

    /// Atomically advance send offset.
    func advanceOffset(by bytes: Int) {
        lock.withLock { _sentOffset += bytes }
    }

    /// Atomically record write failure. Returns (abort, retryDelay).
    func recordWriteFailure() -> (abort: Bool, retryDelay: Double) {
        lock.withLock {
            _writeFailCount += 1
            if _writeFailCount >= 5 {
                _error = APIError.badResponseDetail("write fail buf=\(_buffer.count)")
                _done = true
                return (true, 0)
            }
            _sentOffset = 0
            return (false, 0.1 * Double(_writeFailCount))
        }
    }

    /// Atomically record zero-byte write. Returns true if should abort.
    func recordZeroWrite() -> Bool {
        lock.withLock {
            _zeroWrites += 1
            if _zeroWrites >= 30 {
                _error = APIError.badResponseDetail("write stuck buf=\(_buffer.count)")
                _done = true
                return true
            }
            return false
        }
    }

    /// Atomically mark payload as sent.
    func markSent() {
        lock.withLock { _sent = true }
    }

    /// Atomically check if response is complete and finalize.
    func tryFinalizeOnComplete() -> Bool {
        lock.withLock {
            guard !_done, _result == nil, !_buffer.isEmpty else { return false }
            guard StreamHTTPClient.isResponseComplete(_buffer) else { return false }
            _result = StreamHTTPClient.parseResponse(_buffer)
            _done = true
            return true
        }
    }

    /// Atomically handle EOF: finalize with buffered data if available.
    func handleEOF() -> Bool {
        lock.withLock {
            guard !_done else { return false }
            if !_buffer.isEmpty && _result == nil {
                _result = StreamHTTPClient.parseResponse(_buffer)
            }
            _done = true
            return true
        }
    }

    /// Atomically handle error: try to salvage response from buffer, else set error.
    func handleError(_ error: Error) -> Bool {
        lock.withLock {
            guard !_done else { return false }
            if !_buffer.isEmpty && _result == nil {
                let parsed = StreamHTTPClient.parseResponse(_buffer)
                if parsed.1 > 0 {
                    _result = parsed
                    _done = true
                    return true
                }
            }
            _error = error
            _done = true
            return true
        }
    }

    init(payload: Data?) {
        self._payload = payload
    }
}
