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

            // 环境光晕（液态玻璃透出内容）
            ZStack {
                Circle().fill(Color.blue.opacity(0.30)).frame(width: 300, height: 300).blur(radius: 70)
                    .offset(y: 120)
                Circle().fill(Color.indigo.opacity(0.22)).frame(width: 240, height: 240).blur(radius: 60)
                    .offset(x: 130, y: 90)
                Circle().fill(Color.cyan.opacity(0.15)).frame(width: 200, height: 200).blur(radius: 55)
                    .offset(x: -120, y: 110)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

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
                    .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - 液态玻璃悬浮 Dock（iOS 26 glassEffect + 可拖动）

struct DockBar: View {
    @Binding var selected: DockTab
    @State private var dragOffset: CGFloat = 0

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
            // iOS 26 真液态玻璃（blur + 折射 + 高光，由系统渲染）
            Capsule().fill(.regularMaterial)
        }
        .glassEffect(.regular)
        .clipShape(.capsule)
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(colors: [
                    Color.white.opacity(0.35),
                    Color.white.opacity(0.10)
                ], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8
            )
        }
        .shadow(color: .black.opacity(0.45), radius: 22, y: 9)
        .padding(.horizontal, 26)
        // 液态玻璃交互：按住水平拖动，松手弹簧回弹
        .offset(x: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let velocity = value.predictedEndTranslation.width
                    withAnimation(.spring(duration: 0.5, bounce: 0.35)) {
                        dragOffset = velocity > 300 ? 40 : (velocity < -300 ? -40 : 0)
                    }
                    // 短暂停留后回中
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}
