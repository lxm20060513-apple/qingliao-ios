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
    @Environment(KeyboardObserver.self) private var kb
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var dockVisibility = DockVisibility.shared

    var body: some View {
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
                } else {
                    ChatView().tag(DockTab.chat)
                }
                SessionsView(onOpenSession: { selected = .chat }).tag(DockTab.sessions)
                if CloudConfig.shared.isCloudMode {
                    CloudDashboardView().tag(DockTab.dashboard)
                } else {
                    DashboardView().tag(DockTab.dashboard)
                }
                if CloudConfig.shared.isCloudMode {
                    CloudSettingsView().tag(DockTab.settings)
                } else {
                    SettingsView().tag(DockTab.settings)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(uiColor: .systemBackground))
            .ignoresSafeArea(edges: .bottom)
            .coordinateSpace(name: "scrollspace")
            .animation(.easeInOut(duration: 0.28), value: selected)
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

            VStack {
                Spacer()
                DockBar(selected: $selected)
                    .offset(y: (kb.isVisible || dockVisibility.hidden) ? 120 : 0)
                    .opacity((kb.isVisible || dockVisibility.hidden) ? 0 : 1)
                    .allowsHitTesting(!(kb.isVisible || dockVisibility.hidden))
                    .animation(.spring(duration: 0.5, bounce: 0.25), value: dockVisibility.hidden)
                    .animation(.spring(duration: 0.5, bounce: 0.32), value: kb.isVisible)
                    .gesture(
                        DragGesture(minimumDistance: 25)
                            .onEnded { v in
                                if v.translation.height > 50 {
                                    withAnimation(.spring(duration: 0.5, bounce: 0.25)) { dockVisibility.hidden = true }
                                } else if v.translation.height < -50 {
                                    withAnimation(.spring(duration: 0.5, bounce: 0.25)) { dockVisibility.hidden = false }
                                }
                            }
                    )
                    .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 胶囊 Dock：毛玻璃背景 + 选中项胶囊高亮

struct DockBar: View {
    @Binding var selected: DockTab
    @Environment(\.colorScheme) private var scheme
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DockTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22, weight: .medium))
                            .scaleEffect(tab == .chat && bounce ? 1.18 : 1.0)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selected == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected == tab {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                                .animation(.easeInOut(duration: 0.25), value: selected)
                        }
                    }
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .animation(.easeOut(duration: 0.18), value: selected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.72))   // v3.0.44：更透一点（原 opaque 不透，现在是半透明玻璃）
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.5
            )
        }
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .onReceive(NotificationCenter.default.publisher(for: .qingliaoSent)) { _ in
            withAnimation(.spring(duration: 0.25, bounce: 0.5)) {
                bounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                    bounce = false
                }
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 16)
    }
}
