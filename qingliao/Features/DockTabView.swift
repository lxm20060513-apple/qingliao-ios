import SwiftUI

enum DockTab: String, CaseIterable, Identifiable {
    case chat, sessions, dashboard, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "聊天"
        case .sessions: "会话"
        case .dashboard: "看板"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .chat: "message.fill"
        case .sessions: "clock"
        case .dashboard: "square.grid.2x2.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct DockTabView: View {
    @State private var selected: DockTab = .chat

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 页面滑动切换（TabView page style）
            TabView(selection: $selected) {
                ChatView().tag(DockTab.chat)
                SessionsView().tag(DockTab.sessions)
                DashboardView().tag(DockTab.dashboard)
                SettingsView().tag(DockTab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)

            VStack {
                Spacer()
                DockBar(selected: $selected)
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - 液态玻璃悬浮 Dock（iOS 26 Liquid Glass 风格模拟）

struct DockBar: View {
    @Binding var selected: DockTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DockTab.allCases) { tab in
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { selected = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 21, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(selected == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .background {
                        if selected == tab {
                            Capsule().fill(Color.accentColor.opacity(0.18))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            // 液态玻璃：材质 + 顶部高光渐变 + 环境光晕
            ZStack {
                Capsule().fill(
                    LinearGradient(colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.03)
                    ], startPoint: .top, endPoint: .bottom)
                )
                Capsule().fill(.ultraThinMaterial)
            }
            .clipShape(Capsule())
        }
        .overlay {
            // 高光描边（上亮下暗，模拟玻璃折射）
            Capsule().strokeBorder(
                LinearGradient(colors: [
                    Color.white.opacity(0.28),
                    Color.white.opacity(0.08)
                ], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.9
            )
        }
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .padding(.horizontal, 26)
    }
}
