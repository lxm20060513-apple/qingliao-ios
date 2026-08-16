import ActivityKit

// MARK: - v2.0.114 Live Activity 属性（App 与 Widget Extension 共享编译）

struct QingliaoActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // 回复状态文案（"AI 回复中…" / "回复完成"）
        var status: String
        // 光晕相位 0-1（呼吸效果：App 前台期间周期性 update 透明度）
        var glowPhase: Double = 0
        // 光晕主题色（多彩渐变用，0=蓝紫粉 1=青绿金）
        var theme: Int = 0
    }

    // 开始时间（兜底：超时自动退岛，防 App 退后台后岛卡住）
    var startedAt: Date
    var sessionTitle: String?
}
