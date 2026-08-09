import SwiftUI

// MARK: - 会话页（最近聊天列表 + 滑动删除）

struct SessionItem: Identifiable {
    let id: String
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let time: String
}

struct SessionsView: View {
    @State private var items: [SessionItem] = [
        SessionItem(id: "1", icon: "🧠", iconColor: .blue, title: "Cron: 量化学习模型定时任务", subtitle: "策略在正常运行，收益 +2.3%", time: "28 分钟"),
        SessionItem(id: "2", icon: "🔧", iconColor: .indigo, title: "工具链测试", subtitle: "浏览器 / 终端 / 文件全部通过", time: "2 小时"),
        SessionItem(id: "3", icon: "🧪", iconColor: .green, title: "协议测试", subtitle: "API 鉴权链路验证 OK", time: "昨天"),
        SessionItem(id: "4", icon: "📈", iconColor: .orange, title: "量化学习模型", subtitle: "回测结果已更新", time: "4 天"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "会话", trailing: AnyView(addButton))
            ScrollView {
                VStack(spacing: 10) {
                    BotCard()
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            SessionRow(item: item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            items.removeAll { $0.id == item.id }
                                        }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .glassListCard()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 90)
            }
        }
    }

    private var addButton: some View {
        Button {} label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 机器人卡

struct BotCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("M")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("机器人 main")
                    .font(.system(size: 15, weight: .semibold))
                Text("deepseek/deepseek-v4-flash")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("在线")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
        .padding(13)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.14), Color.indigo.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 0.8)
        )
    }
}

// MARK: - 会话行

struct SessionRow: View {
    let item: SessionItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.icon)
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(item.iconColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.time)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(Rectangle())
    }
}
