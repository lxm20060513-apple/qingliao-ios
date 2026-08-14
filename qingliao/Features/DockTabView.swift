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
    @Environment(AuthStore.self) private var auth   // v2.0.63 通知直达需要
    @Environment(ChatStore.self) private var chat
    @Environment(StreamClient.self) private var stream   // v2.0.87bi：流式期间 dock 保持原位
    @Environment(\.horizontalSizeClass) private var hSize   // v2.0.62 iPad 多栏
    // @Observable 单例必须 @State 持有，body 才能观察其属性变化（否则 hidden 更新不触发重绘）
    @State private var dockVisibility = DockVisibility.shared

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            TabView(selection: $selected) {
                // v2.0.62：iPad 横屏多栏——会话列表 + 聊天同屏
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
                DashboardView().tag(DockTab.dashboard)
                SettingsView().tag(DockTab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(uiColor: .systemBackground))
            .ignoresSafeArea(edges: .bottom)
            .coordinateSpace(name: "scrollspace")
            // 页面切换滑动动画（点击 Dock 时整体横向滑动过渡）
            .animation(.easeInOut(duration: 0.38), value: selected)
            // v2.0.60：通知点击 → 直达对应会话
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

            // 环境光晕：收敛到底部 Dock 区域、低透明度（页面主体保持纯黑，玻璃有内容可透即可）
            ZStack {
                Circle().fill(Color.blue.opacity(0.14)).frame(width: 220, height: 220).blur(radius: 65)
                    .offset(y: 170)
                Circle().fill(Color.indigo.opacity(0.10)).frame(width: 190, height: 190).blur(radius: 55)
                    .offset(x: 140, y: 140)
                Circle().fill(Color.cyan.opacity(0.07)).frame(width: 170, height: 170).blur(radius: 50)
                    .offset(x: -130, y: 150)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            VStack {
                Spacer()
                // 键盘弹出时 Dock 下移淡出（微信 tab bar 行为）；收起时弹簧回落
                // 下滑隐藏 / 上滑显示（scrollPosition 驱动 + Dock 栏拖拽手势兜底）
                // v2.0.87bi：流式回复期间 dock 保持原位（键盘状态触发下移与发光并存 → 根因修复）
                // v2.0.88f：移除 streaming 禁用——87bl 已根治光晕 safe area 干扰（真正根因），
                // streaming 中键盘弹出时 dock 必须正常让路，否则挡住输入框/发送按钮（用户实测）
                DockBar(selected: $selected)
                    .offset(y: (kb.isVisible || dockVisibility.hidden) ? 120 : 0)
                    .opacity((kb.isVisible || dockVisibility.hidden) ? 0 : 1)
                    .allowsHitTesting(!(kb.isVisible || dockVisibility.hidden))
                    .animation(.spring(duration: 0.5, bounce: 0.25), value: dockVisibility.hidden)
                    .animation(.spring(duration: 0.5, bounce: 0.32), value: kb.isVisible)
                    .gesture(
                        // 手势兜底：Dock 栏向下拖 → 隐藏；向上拖 → 显示
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

// MARK: - 液态玻璃 Dock：按住出现玻璃透镜，滑动玻璃切换页面（Dock 本体不动）

struct DockBar: View {
    @Binding var selected: DockTab
    @Environment(\.colorScheme) private var scheme
    @State private var lensX: CGFloat = 0
    @State private var isInteracting = false
    @State private var hoverIdx: Int? = nil   // 手指所在 tab（放大镜用）
    @State private var dockWidth: CGFloat = 280
    // v2.0.65：发送完成 Dock 轻跳
    @State private var bounce = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(DockTab.allCases) { tab in
                    Button {
                        // 交给 TabView 的 .animation(value: selected) 驱动整体滑动
                        selected = tab
                    } label: {
                        VStack(spacing: 4) {
                            // v2.0.86p：选中胶囊已移除（效果不佳，保留变色+轻放大）
                            Image(systemName: tab.icon)
                                .font(.system(size: 21, weight: .medium))
                                // 放大镜效果：透镜所在的 tab 图标放大（松手后短暂保持）
                                // v2.0.65：发送完成时聊天图标轻跳
                                // v2.0.85c：选中态图标轻放大
                                .scaleEffect(hoverIdx == tabIndex(tab) ? 1.45 : (selected == tab ? 1.12 : (tab == .chat && bounce ? 1.18 : 1.0)))
                            Text(tab.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .scaleEffect(hoverIdx == tabIndex(tab) ? 1.3 : 1.0)
                        }
                        .foregroundStyle(selected == tab ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .animation(.spring(duration: 0.3, bounce: 0.4), value: hoverIdx)
                        .animation(.easeOut(duration: 0.18), value: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            // v2.0.87e：原生液态玻璃（iOS 26+，替代 material 模拟）
            .background {
                Capsule().glassEffect()
            }
            .clipShape(.capsule)
            .overlay {
                // 液态玻璃透镜：跟随手指/选中项（半透明蓝，不用 glassEffect——小元素上渲染会变灰块）
                Capsule()
                    .fill(Color.accentColor.opacity(isInteracting ? 0.35 : 0.22))
                    .frame(width: tabWidth(in: geo.size.width) - 8, height: geo.size.height - 10)
                    .offset(x: lensX)
                    .animation(.spring(duration: 0.3, bounce: 0.25), value: lensX)
            }
            .overlay {
                // 顶部高光带（液态玻璃标志性反射，LiquidGlass 视觉签名）
                Capsule()
                    .fill(
                        LinearGradient(colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.03),
                            Color.clear
                        ], startPoint: .top, endPoint: .bottom)
                    )
            }
            .overlay {
                // 外描边：白 0.38→0.10 渐变（顶部亮、底部暗）
                Capsule().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0.10)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8
                )
            }
            .overlay {
                // 内高光描边（GlassShaders premiumShader：0.5pt 白 0.20）
                Capsule()
                    .inset(by: 1.5)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.38), radius: 20, x: 0, y: 8)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isInteracting = true
                        let w = geo.size.width
                        let tw = tabWidth(in: w)
                        // 内容从 padding 12 处开始
                        let idx = min(max(Int((value.location.x - 12) / tw), 0), DockTab.allCases.count - 1)
                        lensX = lensOffset(for: idx)
                        hoverIdx = idx
                        let newTab = DockTab.allCases[idx]
                        if newTab != selected {
                            selected = newTab
                        }
                    }
                    .onEnded { _ in
                        isInteracting = false
                        // 放大短暂保持（点按也能看清放大效果）
                        let lastIdx = hoverIdx
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if hoverIdx == lastIdx {
                                withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                                    hoverIdx = nil
                                }
                            }
                        }
                    }
            )
            .onAppear {
                dockWidth = geo.size.width
                // 延迟到布局完成后设置透镜初始位置（避免 geo 尺寸未就绪）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.none) {
                        lensX = lensOffset(for: DockTab.allCases.firstIndex(of: selected) ?? 0)
                    }
                }
            }
            .onChange(of: selected) {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                    lensX = lensOffset(for: DockTab.allCases.firstIndex(of: selected) ?? 0)
                }
            }
            // v2.0.65：发送完成 → 聊天图标轻跳
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
        }
        .frame(height: 68)
        .padding(.horizontal, 26)
    }

    private func tabWidth(in total: CGFloat) -> CGFloat {
        (total - 24) / CGFloat(DockTab.allCases.count)
    }

    /// 放大镜状态：按住且透镜在当前 tab 上
    private func tabIndex(_ tab: DockTab) -> Int {
        DockTab.allCases.firstIndex(of: tab) ?? 0
    }

    /// 透镜中心相对 Dock 中心的偏移（4 tab 对称：-1.5/-0.5/+0.5/+1.5 倍 tab 宽）
    private func lensOffset(for idx: Int) -> CGFloat {
        let tw = tabWidth(in: dockWidth)
        return (CGFloat(idx) - 1.5) * tw
    }
}
