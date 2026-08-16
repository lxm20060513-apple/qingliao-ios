import WidgetKit
import SwiftUI

// MARK: - v2.0.114 桌面小组件（轻聊速览——打开轻聊；NAS 状态数据后续经 App Group 接入）

struct QingliaoHomeEntry: TimelineEntry {
    let date: Date
}

struct QingliaoHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> QingliaoHomeEntry {
        QingliaoHomeEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (QingliaoHomeEntry) -> Void) {
        completion(QingliaoHomeEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QingliaoHomeEntry>) -> Void) {
        completion(Timeline(entries: [QingliaoHomeEntry(date: Date())], policy: .never))
    }
}

struct QingliaoHomeWidget: Widget {
    let kind: String = "QingliaoHome"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QingliaoHomeProvider()) { _ in
            QingliaoHomeView()
        }
        .configurationDisplayName("轻聊速览")
        .description("轻聊 AI 快捷入口")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QingliaoHomeView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.12), .purple.opacity(0.12), .pink.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: family == .systemSmall ? 8 : 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .indigo, .purple],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: family == .systemSmall ? 16 : 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: family == .systemSmall ? 44 : 52, height: family == .systemSmall ? 44 : 52)
                VStack(spacing: 2) {
                    Text("轻聊")
                        .font(.system(size: family == .systemSmall ? 14 : 16, weight: .bold))
                    Text("点击打开 AI 对话")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(URL(string: "qingliao://chat"))
    }
}
