import Foundation
import UserNotifications

// MARK: - v2.0.36 本地通知（AI 回复完成提醒等）

enum NotificationHelper {
    /// App 启动时请求通知权限
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 发送一条本地通知（App 退后台时用）；v2.0.60 支持携带会话 id（点击直达）
    static func notify(title: String, body: String, sessionId: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let sid = sessionId {
            content.userInfo = ["qingliao_session": sid]
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
