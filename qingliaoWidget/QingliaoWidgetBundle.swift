import WidgetKit
import SwiftUI

// MARK: - v2.0.114 Widget 入口（v2.0.114c：桌面小组件需求未定已移除，仅保留 Live Activity 灵动岛）

@main
struct QingliaoWidgetBundle: WidgetBundle {
    var body: some Widget {
        QingliaoLiveActivity()
    }
}
