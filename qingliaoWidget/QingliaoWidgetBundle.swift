import WidgetKit
import SwiftUI

// MARK: - v2.0.114 Widget 入口（桌面小组件 + Live Activity 回复岛）

@main
struct QingliaoWidgetBundle: WidgetBundle {
    var body: some Widget {
        QingliaoLiveActivity()
        QingliaoHomeWidget()
    }
}
