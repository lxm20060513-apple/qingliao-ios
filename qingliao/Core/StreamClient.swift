import Foundation
import Observation

// MARK: - 流式客户端：与 PWA 相同协议（后端持流写文件，前端轮询增量）
// POST /api/stream/start {sessionId, model, provider, messages, pushEnabled} -> {taskId}
// GET  /api/stream/{taskId}?offset=N -> {content: 增量, done, status, error}
// 轮询间隔自适应：800ms 起 -> 有内容 500ms -> 连续 3 次空 2000ms；连续失败 10 次停止

@MainActor
@Observable
final class StreamClient {
    var content = ""          // 累计全文
    var isStreaming = false
    var isDone = false
    var status = ""
    var errorMessage = ""

    private var taskId = ""
    private var offset = 0
    private var failCount = 0
    private var idleStreak = 0
    private var interval: TimeInterval = 0.8
    private var pollTask: Task<Void, Never>?
    private var onFinished: ((Bool, String) -> Void)?   // (success, errorMessage)

    /// 启动流式请求
    func start(auth: AuthStore, sessionId: String, model: String, provider: String,
               messages: [[String: Any]], onFinished: ((Bool, String) -> Void)? = nil) async {
        stopPolling()
        content = ""
        offset = 0
        failCount = 0
        idleStreak = 0
        interval = 0.8
        isStreaming = true
        isDone = false
        status = ""
        errorMessage = ""
        self.onFinished = onFinished

        do {
            let body: [String: Any] = [
                "sessionId": sessionId,
                "model": model,
                "provider": provider,
                "messages": messages,
                "pushEnabled": false
            ]
            let (data, _) = try await auth.request("/api/stream/start", method: "POST", body: body)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tid = json["taskId"] as? String else {
                finish(success: false, error: "启动失败：服务器响应异常")
                return
            }
            taskId = tid
            startPolling(auth: auth)
        } catch {
            finish(success: false, error: "无法连接服务器")
        }
    }

    /// 主动停止
    func stop(auth: AuthStore) {
        stopPolling()
        if !taskId.isEmpty, !isDone {
            Task {
                try? await auth.request("/api/stream/\(taskId)/stop", method: "POST")
            }
        }
        if isStreaming, !isDone {
            finish(success: false, error: "已停止")
        }
    }

    // MARK: - 轮询

    private func startPolling(auth: AuthStore) {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isDone else { break }
                await self.pollOnce(auth: auth)
                if self.isDone { break }
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce(auth: AuthStore) async {
        do {
            let (data, _) = try await auth.request("/api/stream/\(taskId)?offset=\(offset)")
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                failCount += 1
                if failCount >= 10 { finish(success: false, error: "连接中断，请重试") }
                return
            }
            failCount = 0
            if let c = j["content"] as? String, !c.isEmpty {
                offset += c.count
                content += c
                idleStreak = 0
                if interval != 0.5 { interval = 0.5 }
            } else if !(j["done"] as? Bool ?? false) {
                idleStreak += 1
                if idleStreak >= 3 && interval != 2.0 { interval = 2.0 }
            }
            if j["done"] as? Bool ?? false {
                let st = j["status"] as? String ?? "done"
                let err = j["error"] as? String ?? ""
                finish(success: st != "error", error: err)
            }
        } catch {
            failCount += 1
            if failCount >= 10 {
                finish(success: false, error: "连接中断，请重试")
            }
        }
    }

    private func finish(success: Bool, error: String) {
        isStreaming = false
        isDone = true
        status = success ? "done" : "error"
        errorMessage = error
        stopPolling()
        onFinished?(success, error)
        onFinished = nil
    }
}
