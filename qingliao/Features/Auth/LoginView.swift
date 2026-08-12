import SwiftUI

// MARK: - 登录页（服务器地址 + 账号密码 + 记住登录）

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @State private var username = "qingliao"
    @State private var password = ""   // 不预填默认密码（防泄漏默认值）
    // v2.0.55：预填已保存的服务器地址（之前每次登录都要重输）
    @State private var server = UserDefaults.standard.string(forKey: "qingliao_server") ?? ""
    @State private var remember = true
    @State private var testing = false
    @State private var testResult: String?

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
                    // v2.0.71：历史地址胶囊（多地址快速切换，长按删除）
                    if !auth.serverHistory.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(auth.serverHistory, id: \.self) { addr in
                                    Button {
                                        server = addr
                                    } label: {
                                        Text(addr)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 6)
                                            .background(Color.accentColor.opacity(0.12))
                                            .clipShape(Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            auth.removeServer(addr)
                                        } label: {
                                            Label("删除此地址", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 30)
                        .padding(.top, -2)
                    }
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
                    // 先提交服务器地址（登录页可修改），再登录
                    // v2.0.55：必须持久化到 UserDefaults——只改内存的话 App 重启/ASWAS
                    // 流程读默认值 example.com 导致登录弹窗异常（用户实测）
                    let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
                    auth.saveServer(s)
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

                // 测试连接按钮
                Button {
                    testing = true
                    testResult = nil
                    Task {
                        let r = await auth.testConnection(server: server)
                        testResult = r
                        testing = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: testing ? "arrow.trianglehead.2.clockwise.rotate.90" : "network")
                            .font(.system(size: 13))
                        Text(testing ? "测试中..." : "测试连接")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .disabled(testing || auth.isLoading)

                if let tr = testResult {
                    Text(tr)
                        .font(.system(size: 12))
                        .foregroundStyle(tr.hasPrefix("✅") ? Color.green : (tr.hasPrefix("⚠️") ? Color.orange : Color.red))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 6)
                }

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
