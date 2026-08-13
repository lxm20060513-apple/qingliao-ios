import SwiftUI

// MARK: - Dock 显示状态（v2.0.86h：滑动隐藏从未生效已删除，仅保留手动隐藏开关）

@MainActor
@Observable
final class DockVisibility {
    static let shared = DockVisibility()
    var hidden = false
    var forceHidden = false   // v2.0.45：设置"隐藏 Dock 栏"开关强制隐藏

    func reset() {
        hidden = forceHidden   // v2.0.45：强制隐藏时 reset 也不显示
    }
}
