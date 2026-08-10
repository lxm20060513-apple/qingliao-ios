import SwiftUI

@main
struct QingliaoApp: App {
    @State private var auth = AuthStore()
    @State private var chat = ChatStore()
    @State private var stream = StreamClient()
    @State private var keyboard = KeyboardObserver()
    @AppStorage("qingliao_appearance") private var appearance = "dark"   // dark / light / system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(chat)
                .environment(stream)
                .environment(keyboard)
                .preferredColorScheme(colorScheme)
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

    var body: some View {
        // 免登录模式（iOS 27 蜂窝上行挂起，密码登录请求发不出；服务器已开 AUTO_LOGIN 免鉴权）
        DockTabView()
    }
}
