import SwiftUI

// MARK: - Dock 滚动隐藏状态（下滑隐藏 / 上滑显示，全局共享）

@MainActor
@Observable
final class DockVisibility {
    static let shared = DockVisibility()
    var hidden = false

    /// 由各页面 ScrollView 上报滚动位置 y（内容向下滚动时 y 增大，回顶为 0/负）
    /// 位置阈值判定（比方向差分更可靠）：向下滚 40pt 隐藏，回到顶部显示
    func update(_ y: CGFloat) {
        if y > 40 {
            hidden = true
        } else if y <= 0 {
            hidden = false
        }
    }

    func reset() {
        hidden = false
    }
}
