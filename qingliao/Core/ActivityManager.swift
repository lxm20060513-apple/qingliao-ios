// v2.0.114：@preconcurrency 抑制 ActivityKit 的 Activity 非 Sendable 跨 Task 警告（Swift 6）
@preconcurrency import ActivityKit
import Foundation

// MARK: - v2.0.114 AI 回复过程灵动岛（ActivityKit，无需 entitlement，侧载可用）

@MainActor
enum ActivityManager {
    static var current: Activity<QingliaoActivityAttributes>?
    private static var glowTimer: Timer?

    /// 回复开始上岛（多彩光晕 + 呼吸）
    /// v2.0.114b：设置页开关 qingliao_live_activity（默认开）
    static func startReply(sessionTitle: String?) {
        let enabled = UserDefaults.standard.object(forKey: "qingliao_live_activity") as? Bool ?? true
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = QingliaoActivityAttributes(startedAt: Date(), sessionTitle: sessionTitle)
        let state = QingliaoActivityAttributes.ContentState(status: "AI 回复中…", glowPhase: 0, theme: 0)
        do {
            let activity = try Activity.request(attributes: attrs, contentState: state, pushType: nil)
            current = activity
            startGlow()
        } catch {
            current = nil
        }
    }

    /// 回复完成退岛（先显示完成态 1.5 秒再退）
    static func endReply() {
        stopGlow()
        guard let a = current else { return }
        current = nil
        let final = QingliaoActivityAttributes.ContentState(status: "✅ 回复完成", glowPhase: 1, theme: 0)
        Task {
            try? await a.update(using: final)
            try? await Task.sleep(for: .seconds(1.5))
            await a.end(using: final, dismissalPolicy: .immediate)
        }
    }

    /// 回复失败退岛
    static func failReply() {
        stopGlow()
        guard let a = current else { return }
        current = nil
        let final = QingliaoActivityAttributes.ContentState(status: "⚠️ 回复失败", glowPhase: 1, theme: 0)
        Task {
            try? await a.update(using: final)
            try? await Task.sleep(for: .seconds(1.5))
            await a.end(using: final, dismissalPolicy: .immediate)
        }
    }

    /// 呼吸效果：前台期间周期性更新光晕相位（0.8s 周期，ActivityKit 更新预算内）
    private static func startGlow() {
        stopGlow()
        glowTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                guard let a = current else {
                    stopGlow()
                    return
                }
                let phase = (Date().timeIntervalSince1970 * 1.25)
                    .truncatingRemainder(dividingBy: 1)
                let state = QingliaoActivityAttributes.ContentState(status: "AI 回复中…", glowPhase: phase, theme: 0)
                try? await a.update(using: state)
            }
        }
    }

    private static func stopGlow() {
        glowTimer?.invalidate()
        glowTimer = nil
    }
}
