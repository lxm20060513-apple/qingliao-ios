import Foundation
import Observation

// MARK: - 流式客户端：Safari Relay 版
// 上行：POST /r/stream/start/{uid}（relay 中转，Safari 进程发请求）
// 下行：GET  /r/stream/poll/{uid}/{taskId}/{offset}（路径参数无 query → CFStream 直连）
// 停止：POST /r/stream/stop/{uid}/{taskId}（relay 中转）
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

        // 记录当前流式会话（relay uid 推导用）
        auth.currentStreamSessionId = sessionId

        do {
            let tid = try await auth.streamStart(sessionId: sessionId, model: model,
                                                 provider: provider, messages: messages)
            taskId = tid
            startPolling(auth: auth)
        } catch APIError.relayCancelled {
            finish(success: false, error: "已取消")
        } catch {
            finish(success: false, error: "启动失败：\(error.localizedDescription)")
        }
    }

    /// 主动停止
    func stop(auth: AuthStore) {
        stopPolling()
        if !taskId.isEmpty, !isDone {
            Task { await auth.streamStop(taskId: taskId) }
        }
        if isStreaming, !isDone {
            finish(success: false, error: "已停止")
        }
    }

    // MARK: - 轮询（直连路径参数版）

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
            let (c, done, st, err) = try await auth.streamPoll(taskId: taskId, offset: offset)
            failCount = 0
            if !c.isEmpty {
                offset += c.count
                content += c
                idleStreak = 0
                if interval != 0.15 { interval = 0.15 }   // 有内容时 0.15s 高频轮询（接近逐字）
            } else if !done {
                idleStreak += 1
                // 空 poll 保持 0.4s——首 token 思考期（10-20s）不增加等待感
                if idleStreak >= 3 && interval != 0.4 { interval = 0.4 }
            }
            if done {
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
