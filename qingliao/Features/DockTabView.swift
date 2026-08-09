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

            TabView(selection: $selected) {
                ChatView().tag(DockTab.chat)
                SessionsView().tag(DockTab.sessions)
                DashboardView().tag(DockTab.dashboard)
                SettingsView().tag(DockTab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)

            // 环境光晕（液态玻璃透出内容）
            ZStack {
                Circle().fill(Color.blue.opacity(0.30)).frame(width: 300, height: 300).blur(radius: 70)
                    .offset(y: 120)
                Circle().fill(Color.indigo.opacity(0.22)).frame(width: 240, height: 240).blur(radius: 60)
                    .offset(x: 130, y: 90)
                Circle().fill(Color.cyan.opacity(0.15)).frame(width: 200, height: 200).blur(radius: 55)
                    .offset(x: -120, y: 110)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            VStack {
                Spacer()
                DockBar(selected: $selected)
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
                            Text(tab.title)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(selected == tab ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
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
                // 液态玻璃透镜：跟随手指/选中项
                Capsule()
                    .fill(Color.accentColor.opacity(isInteracting ? 0.32 : 0.18))
                    .frame(width: tabWidth(in: geo.size.width) - 6, height: geo.size.height - 8)
                    .offset(x: lensX)
                    .glassEffect(.regular)
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
                        let idx = min(max(Int(value.location.x / tw), 0), DockTab.allCases.count - 1)
                        lensX = lensOffset(for: idx, width: w)
                        let newTab = DockTab.allCases[idx]
                        if newTab != selected {
                            selected = newTab
                        }
                    }
                    .onEnded { _ in
                        isInteracting = false
                    }
            )
            .onAppear {
                dockWidth = geo.size.width
                lensX = lensOffset(for: DockTab.allCases.firstIndex(of: selected) ?? 0, width: geo.size.width)
            }
            .onChange(of: selected) {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                    lensX = lensOffset(for: DockTab.allCases.firstIndex(of: selected) ?? 0, width: dockWidth)
                }
            }
        }
        .frame(height: 68)
        .padding(.horizontal, 26)
    }

    private func tabWidth(in total: CGFloat) -> CGFloat {
        (total - 24) / CGFloat(DockTab.allCases.count)
    }

    /// 透镜中心相对 Dock 中心的偏移
    private func lensOffset(for idx: Int, width total: CGFloat) -> CGFloat {
        let tw = tabWidth(in: total)
        let center = (CGFloat(idx) + 0.5) * tw
        return center - total / 2
    }
}
