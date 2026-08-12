import SwiftUI

@main
struct QingliaoApp: App {
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
        }
    }

    init() {
        // v2.0.43：崩溃捕获（写本地文件），登录后由 RootView 上报
        CrashReporter.install()
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
    @State private var showSplash = true

    var body: some View {
        ZStack {
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
