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
            // v3.0.60：移除紧贴内容层的纯色 systemBackground——它掐死了液态玻璃对下方内容的折射/采样。
            // （保留 ZStack 最底层背景作兜底，Tab 页自身内容背景照常铺满，玻璃能透出页面内容。）
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
    // v3.0.44：Dock 透明度（设置→外观调节，默认1.0）
    @AppStorage("qingliao_dock_opacity") private var dockOpacity = 1.0

    var body: some View {
        // v3.0.62：真液态玻璃 + 交互式。
        // 关键 1：.glassEffect(.regular.interactive()) 必须加在每个 tab 的 Button 上（交互控件才有按压放大/流动折射语义，
        //         加在 background 玻璃上不会响应触摸——这就是之前"按压没反应"的根因）。
        // 关键 2：GlassEffectContainer 让相邻玻璃按钮统一采样/渲染/变形（官方推荐分组）。
        // 关键 3：默认 .regular = 满强度液态玻璃；去掉按钮内 clipShape + 整条 background 玻璃，避免削弱通透。
        GlassEffectContainer(spacing: 4) {
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
                        .contentShape(Rectangle())
                        .animation(.easeOut(duration: 0.18), value: selected)
                    }
                    .buttonStyle(.plain)
                    // 真液态玻璃 + 交互（按压放大/流动折射）。放 Button 上，不放 background。
                    .glassEffect(.regular.interactive())
                    .padding(4)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        // dockOpacity 保留控制整栏透明度（默认1.0=玻璃满强度，调低整体变淡）——避免设置页滑条失效
        .opacity(dockOpacity)
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
