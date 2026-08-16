import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - v2.0.114 AI 回复过程灵动岛（多彩光晕 + 呼吸）

/// 多彩光晕渐变（蓝紫粉 → 青绿金，随 theme 切换）
func glowGradient(_ theme: Int) -> LinearGradient {
    if theme % 2 == 1 {
        return LinearGradient(colors: [.mint, .green, .yellow],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    return LinearGradient(colors: [.blue, .indigo, .pink, .purple],
                          startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct QingliaoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QingliaoActivityAttributes.self) { context in
            // 锁屏/横幅样式（展开卡片）
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(glowGradient(context.state.theme).opacity(0.5 + 0.5 * context.state.glowPhase))
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.status)
                        .font(.system(size: 14, weight: .semibold))
                    Text("轻聊 AI" + (context.attributes.sessionTitle.map { " · \($0)" } ?? ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(glowGradient(context.state.theme).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开区域
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(glowGradient(context.state.theme),
                                    in: Circle())
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.status)
                            .font(.system(size: 13, weight: .semibold))
                        if let t = context.attributes.sessionTitle {
                            Text(t)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // 多彩光晕条（呼吸：透明度随 glowPhase 变化）
                    RoundedRectangle(cornerRadius: 3)
                        .fill(glowGradient(context.state.theme))
                        .opacity(0.35 + 0.65 * context.state.glowPhase)
                        .frame(height: 4)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(glowGradient(context.state.theme),
                                in: Circle())
            } compactTrailing: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(glowGradient(context.state.theme))
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(glowGradient(context.state.theme))
            }
        }
    }
}
