import SwiftUI

// MARK: - Dock 滚动隐藏状态（下滑隐藏 / 上滑显示，全局共享）

@MainActor
@Observable
final class DockVisibility {
    static let shared = DockVisibility()
    var hidden = false
    private var lastOffset: CGFloat = 0

    /// 由各页面 ScrollView 上报滚动 offset（值越大越靠近顶部）
    func update(_ offset: CGFloat) {
        let delta = offset - lastOffset
        lastOffset = offset
        // 下滑（内容向下滚，offset 减小）超过阈值 → 隐藏；上滑 → 显示
        if delta < -40 {
            hidden = true
        } else if delta > 40 || offset >= 0 {
            hidden = false
        }
    }

    func reset() {
        hidden = false
        lastOffset = 0
    }
}

/// ScrollView 滚动 offset 上报（配合 DockVisibility）
struct ScrollOffsetKey: PreferenceKey {
    nonisolated static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// 挂到**可滚动内容**上（VStack/LazyVStack 内部）：上报滚动方向 → Dock 下滑隐藏/上滑显示
    /// 注意：必须挂在内容上而非 ScrollView 外层（外层 background 不随滚动，offset 恒定）
    func dockScrollAware() -> some View {
        self
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                           value: geo.frame(in: .named("scrollspace")).minY)
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { v in
                DockVisibility.shared.update(v)
            }
    }
}
