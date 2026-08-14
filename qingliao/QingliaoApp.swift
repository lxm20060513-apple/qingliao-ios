import SwiftUI

@main
struct QingliaoApp: App {
    // v2.0.60：通知点击直达会话（AppDelegate 捕获）
    @UIApplicationDelegateAdaptor(QingliaoAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase   // v2.0.61 流式持久化
    @State private var auth = AuthStore()
    @State private var chat = ChatStore()
    @State private var stream = StreamClient()
    @State private var keyboard = KeyboardObserver()
    @AppStorage("qingliao_appearance") private var appearance = "system"   // dark / light / system（v2.0.42 默认跟随系统，与 SettingsView 默认值一致）

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(chat)
                .environment(stream)
                .environment(keyboard)
                .preferredColorScheme(colorScheme)
                .task {
                    // v2.0.36：请求本地通知权限（AI 回复完成提醒）
                    NotificationHelper.requestAuth()
                }
                // v2.0.61：App 进后台时持久化流式状态（杀后台可恢复）
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        stream.persistState(sessionId: chat.sessionId)
                    }
                    // v2.0.87t：前台恢复自动重连（蜂窝 IPv6 会话后台过期 → 重建，免手动飞行模式）
                    if phase == .active {
                        Task { await auth.refreshConnection() }
                    }
                }
        }
    }

    init() {
        // v2.0.43：崩溃捕获（写本地文件），登录后由 RootView 上报
        CrashReporter.install()
        // v2.0.45：应用"隐藏 Dock 栏"设置（启动即生效）
        if UserDefaults.standard.bool(forKey: "qingliao_hide_dock") {
            DockVisibility.shared.forceHidden = true
            DockVisibility.shared.hidden = true
        }
    }

    /// 外观：跟随用户选择（深色 #000 / 白天 #FFF / 跟随系统）
    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StreamClient.self) private var stream   // v2.0.87bd：Siri 发光读取流式状态
    @State private var showSplash = true

    var body: some View {
        ZStack {
            // v2.0.87bf：AI 回答时 Siri 边框发光（先渲染 → DockTabView 在上层，dock 不被盖且半透明透出底部光晕）
            if stream.isStreaming && UserDefaults.standard.bool(forKey: "qingliao_siri_glow") {
                SiriGlowOverlay()
            }

            // 登录门禁：未登录显示登录页，登录后进主界面（登录状态 UserDefaults 持久化）
            if auth.isLoggedIn {
                DockTabView()
            } else {
                LoginView()
            }

            // 启动动画：一次淡入后淡出
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task {
            // v2.0.43：登录态下上报上次崩溃（不阻塞启动）
            if auth.isLoggedIn {
                await CrashReporter.flushPending(auth: auth)
            }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
        }
    }
}
