import SwiftUI

@main
struct QingliaoApp: App {
    @State private var auth = AuthStore()
    @State private var chat = ChatStore()
    @State private var stream = StreamClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(chat)
                .environment(stream)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        if auth.isLoggedIn {
            DockTabView()
        } else {
            LoginView()
        }
    }
}
