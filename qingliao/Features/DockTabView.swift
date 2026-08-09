import SwiftUI

enum DockTab: CaseIterable, Identifiable {
    case chat, sessions, dashboard, settings

    var id: Self { self }

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

            Group {
                switch selected {
                case .chat: ChatView()
                case .sessions: SessionsView()
                case .dashboard: DashboardView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()
                DockBar(selected: $selected)
                    .padding(.bottom, 6)
            }
        }
    }
}

// MARK: - 液态玻璃悬浮 Dock

struct DockBar: View {
    @Binding var selected: DockTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DockTab.allCases) { tab in
                Button {
                    withAnimation(.spring(duration: 0.35)) { selected = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundStyle(selected == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background {
                        if selected == tab {
                            Capsule().fill(Color.accentColor.opacity(0.16))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 7)
        .padding(.horizontal, 28)
    }
}
