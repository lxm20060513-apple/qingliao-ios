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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selected) {
                ChatView().tag(DockTab.chat)
                SessionsView(onOpenSession: { selected = .chat }).tag(DockTab.sessions)
                DashboardView().tag(DockTab.dashboard)
                SettingsView(onOpenSessions: { selected = .sessions }).tag(DockTab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)

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
                DockBar(selected: $selected)
                    .offset(y: kb.isVisible ? 40 : 0)
                    .opacity(kb.isVisible ? 0 : 1)
                    .allowsHitTesting(!kb.isVisible)
                    .animation(.spring(duration: 0.5, bounce: 0.32), value: kb.isVisible)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - 液态玻璃 Dock：按住出现玻璃透镜，滑动玻璃切换页面（Dock 本体不动）

struct DockBar: View {
    @Binding var selected: DockTab
    @State private var lensX: CGFloat = 0
    @State private var isInteracting = false
    @State private var hoverIdx: Int? = nil   // 手指所在 tab（放大镜用）
    @State private var dockWidth: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(DockTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { selected = tab }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 21, weight: .medium))
                                // 放大镜效果：透镜所在的 tab 图标放大（松手后短暂保持）
                                .scaleEffect(hoverIdx == tabIndex(tab) ? 1.45 : 1.0)
                            Text(tab.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .scaleEffect(hoverIdx == tabIndex(tab) ? 1.3 : 1.0)
                        }
                        .foregroundStyle(selected == tab ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .animation(.spring(duration: 0.3, bounce: 0.4), value: hoverIdx)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background { Capsule().fill(.regularMaterial) }
            .glassEffect(.regular)
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
                Capsule().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.10)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8
                )
            }
            .shadow(color: .black.opacity(0.45), radius: 22, y: 9)
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
