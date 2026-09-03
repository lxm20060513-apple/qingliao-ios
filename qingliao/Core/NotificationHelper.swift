import Foundation
import UserNotifications

// MARK: - v2.0.36 本地通知（AI 回复完成提醒等）

enum NotificationHelper {
    /// App 启动时请求通知权限（记录结果，便于排查通知不弹的问题）
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("[NOTIFY] auth error: \(error)") }
            if !granted { NSLog("[NOTIFY] ⚠️ 通知权限被拒绝，AI 回复完成提醒将不可用") }
        }
    }

    /// 发送一条本地通知（App 退后台时用）；v2.0.60 支持携带会话 id（点击直达）
    /// v3.0.x fix：使用语义化 identifier 支持同内容通知替换（防快速连续推送堆叠多条）
    static func notify(title: String, body: String, sessionId: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let sid = sessionId {
            content.userInfo = ["qingliao_session": sid]
        }
        // 用固定前缀 + 内容哈希做 identifier，相同内容会替换旧通知（不堆叠）
        let hash = body.hashValue
        let identifier = "qingliao_push_\(abs(hash))"
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
