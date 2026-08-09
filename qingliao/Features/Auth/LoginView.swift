import SwiftUI

// MARK: - 登录页（服务器地址 + 账号密码 + 记住登录）

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @State private var username = "qingliao"
    @State private var password = ""
    @State private var server = ""
    @State private var remember = true

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("轻聊")
                        .font(.system(size: 28, weight: .bold))
                    Text("家庭 NAS 上的 AI 助手")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                // 表单
                VStack(spacing: 12) {
                    GlassField(icon: "globe", placeholder: "服务器地址", text: $server)
                    GlassField(icon: "person", placeholder: "用户名", text: $username)
                    GlassField(icon: "lock", placeholder: "密码", text: $password, isSecure: true)
                }
                .padding(.horizontal, 28)

                // 记住登录
                Toggle(isOn: $remember) {
                    Text("记住登录（7 天免登录）")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .tint(.blue)
                .padding(.horizontal, 28)

                if let err = auth.errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // 登录按钮
                Button {
                    Task {
                        await auth.login(username: username, password: password, remember: remember)
                    }
                } label: {
                    Text(auth.isLoading ? "登录中..." : "登 录")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .disabled(auth.isLoading)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            if server.isEmpty {
                server = auth.serverURL
            }
        }
    }
}

struct GlassField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}
