import SwiftUI

@main
struct QingliaoApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
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
