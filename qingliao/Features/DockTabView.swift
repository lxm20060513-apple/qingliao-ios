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
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        // v3.0.64：改用 iOS 26 系统原生 TabView tab bar —— 系统自动渲染液态玻璃 tab bar，
        // 自带按压放大/流动折射/边缘高光（即用户要的控制中心那种原生效果）。
        // 弃自定义 DockBar / DockVisibility / 手势（系统 tab bar 原生支持这些，无需自研）。
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            TabView(selection: $selected) {
                if hSize == .regular {
                    HStack(spacing: 0) {
                        SessionsView(onOpenSession: nil)
                            .frame(width: 320)
                            .background(Color(uiColor: .systemBackground))
                        Divider().opacity(0.3)
                        ChatView()
                    }
                    .tag(DockTab.chat)
                    .tabItem { Label(DockTab.chat.title, systemImage: DockTab.chat.icon) }
                } else {
                    ChatView()
                        .tag(DockTab.chat)
                        .tabItem { Label(DockTab.chat.title, systemImage: DockTab.chat.icon) }
                }
                SessionsView(onOpenSession: { selected = .chat })
                    .tag(DockTab.sessions)
                    .tabItem { Label(DockTab.sessions.title, systemImage: DockTab.sessions.icon) }
                if CloudConfig.shared.isCloudMode {
                    CloudDashboardView().tag(DockTab.dashboard)
                        .tabItem { Label(DockTab.dashboard.title, systemImage: DockTab.dashboard.icon) }
                } else {
                    DashboardView().tag(DockTab.dashboard)
                        .tabItem { Label(DockTab.dashboard.title, systemImage: DockTab.dashboard.icon) }
                }
                if CloudConfig.shared.isCloudMode {
                    CloudSettingsView().tag(DockTab.settings)
                        .tabItem { Label(DockTab.settings.title, systemImage: DockTab.settings.icon) }
                } else {
                    SettingsView().tag(DockTab.settings)
                        .tabItem { Label(DockTab.settings.title, systemImage: DockTab.settings.icon) }
                }
            }
            // v3.0.60 回顾：系统 tab bar 自行处理滚动边缘玻璃；此处不再加纯色背景掐死折射
            .onChange(of: selected) { _, new in
                if new != .dashboard {
                    NotificationCenter.default.post(name: .qingliaoDashboardLeave, object: nil)
                }
                if new == .dashboard {
                    NotificationCenter.default.post(name: .qingliaoDashboardRefresh, object: nil)
                }
            }
            .task {
                guard let sid = UserDefaults.standard.string(forKey: "qingliao_open_session") else { return }
                UserDefaults.standard.removeObject(forKey: "qingliao_open_session")
                if let arr = try? await auth.jsonArray("/api/sessions/list") {
                    let sessions = arr.compactMap { ChatSession.parse($0 as? [String: Any] ?? [:]) }
                    if let s = sessions.first(where: { $0.id == sid }) {
                        chat.load(s)
                        selected = .chat
                    }
                }
            }
        }
    }
}
