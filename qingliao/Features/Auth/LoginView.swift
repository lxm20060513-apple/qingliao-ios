import SwiftUI
import LocalAuthentication

// MARK: - 登录页（服务器地址 + 账号密码 + 记住登录 + Face ID 快捷登录）

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @State private var username = "qingliao"
    @State private var password = ""   // 不预填默认密码（防泄漏默认值）
    // v2.0.55：预填已保存的服务器地址（之前每次登录都要重输）
    @State private var server = UserDefaults.standard.string(forKey: "qingliao_server") ?? ""
    // v2.0.72：历史地址抽屉展开
    @State private var showHistory = false
    @State private var remember = true
    @State private var testing = false
    @State private var testResult: String?
    // v2.0.88：Face ID 快捷登录（开关开启即显示按钮；无凭据时点击提示先手动登录）
    @State private var faceIDReady = false
    @State private var showFaceIDHint = false

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
                    // v2.0.72：服务器地址输入框 + 抽屉式历史记录（点击展开）
                    GlassField(icon: "globe", placeholder: "服务器地址", text: $server)
                        .overlay(alignment: .trailing) {
                            if !auth.serverHistory.isEmpty {
                                Button {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                        showHistory.toggle()
                                    }
                                } label: {
                                    Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.secondary)
                                        .padding(.trailing, 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    if showHistory {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(auth.serverHistory, id: \.self) { addr in
                                HStack {
                                    Button {
                                        server = addr
                                        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { showHistory = false }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                            Text(addr)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        auth.removeServer(addr)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                Divider().padding(.leading, 14)
                            }
                        }
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity.combined(with: .move(edge: .top)))
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

                // v2.0.88：Face ID 快捷登录（开关开启即显示；v2.0.88f 放宽——无凭据时提示先登录）
                if faceIDReady {
                    Button {
                        guard let cred = FaceIDStore.load() else {
                            // 还没有保存的凭据（首次使用/开关刚打开）：引导先手动登录一次
                            showFaceIDHint = true
                            return
                        }
                        let context = LAContext()
                        context.localizedReason = "验证后自动登录轻聊"
                        context.evaluatePolicy(.deviceOwnerAuthentication,
                                               localizedReason: "验证后自动登录轻聊") { success, _ in
                            DispatchQueue.main.async {
                                guard success, let cred = FaceIDStore.load() else { return }
                                // 用保存的服务器/账号/密码自动登录（失败会显示错误，可重试/手动登录）
                                auth.saveServer(cred.server)
                                Task { await auth.login(username: cred.username, password: cred.password, remember: true) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "faceid")
                                .font(.system(size: 15))
                            Text(auth.isLoading ? "登录中..." : "Face ID 登录")
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
                    .disabled(auth.isLoading)
                    .alert("尚未保存登录凭据", isPresented: $showFaceIDHint) {
                        Button("好的", role: .cancel) {}
                    } message: {
                        Text("请先手动登录一次，登录后会自动保存凭据，下次即可使用 Face ID 一键登录。")
                    }
                }

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
            refreshFaceID()
        }
        .onChange(of: server) { _, _ in
            refreshFaceID()
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if !loggedIn {
                refreshFaceID()   // 登出回到登录页时刷新（可能凭据已更新）
            }
        }
    }

    /// v2.0.88：Face ID 按钮显示条件 = 开关开启（v2.0.88f：不再要求已有凭据/服务器匹配，
    /// 无凭据时点击会提示先手动登录一次）
    private func refreshFaceID() {
        let on = UserDefaults.standard.object(forKey: "qingliao_faceid_login") as? Bool ?? true
        faceIDReady = on
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
