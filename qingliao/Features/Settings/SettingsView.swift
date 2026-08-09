import SwiftUI

// MARK: - 设置页（iOS 设置风格分组列表，全部功能行可用）

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth

    @State private var showServerSheet = false
    @State private var showPasswordSheet = false
    @State private var showFiles = false
    @State private var showTasks = false
    @State private var showLogs = false
    @State private var testResult: String?
    @State private var testing = false

    var onOpenSessions: (() -> Void)? = nil   // 历史会话 → 跳 Dock 会话 tab

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "设置")
            ScrollView {
                VStack(spacing: 0) {
                    // 账号
                    SectionHeader("账号")
                    VStack(spacing: 0) {
                        SettingRow(icon: "person.crop.circle.fill", iconColor: .blue, title: auth.username, value: "已登录")
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "key.horizontal.fill", iconColor: .gray, title: "修改密码", chevron: true)
                            .onTapGesture { showPasswordSheet = true }
                    }
                    .glassListCard()

                    // 连接
                    SectionHeader("连接")
                    VStack(spacing: 0) {
                        SettingRow(icon: "globe.asia.australia.fill", iconColor: .green, title: "服务器地址", value: shortServer, chevron: true)
                            .onTapGesture { showServerSheet = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "cpu.fill", iconColor: .orange, title: "默认模型", value: "v4-flash")
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "network", iconColor: .blue, title: "测试连接", value: testing ? "检测中..." : nil, chevron: !testing)
                            .onTapGesture { testConnection() }
                    }
                    .glassListCard()

                    // 功能
                    SectionHeader("功能")
                    VStack(spacing: 0) {
                        SettingRow(icon: "folder.fill", iconColor: .indigo, title: "文件管理", chevron: true)
                            .onTapGesture { showFiles = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "clock.badge.fill", iconColor: .red, title: "定时任务", chevron: true)
                            .onTapGesture { showTasks = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "doc.text.fill", iconColor: .orange, title: "日志", chevron: true)
                            .onTapGesture { showLogs = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "clock.arrow.circlepath", iconColor: .cyan, title: "历史会话", chevron: true)
                            .onTapGesture { onOpenSessions?() }
                    }
                    .glassListCard()

                    // 其他
                    SectionHeader("其他")
                    VStack(spacing: 0) {
                        SettingRow(icon: "info.circle.fill", iconColor: .gray, title: "关于轻聊", value: "2.0")
                        Divider().padding(.leading, 52)
                        Button {
                            auth.logout()
                        } label: {
                            HStack {
                                Spacer()
                                Text("退出登录")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .glassListCard()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showServerSheet) {
            ServerSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showFiles) {
            FilesView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showTasks) {
            TasksView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLogs) {
            LogsView()
                .presentationDetents([.medium, .large])
        }
        .alert("测试连接", isPresented: Binding(get: { testResult != nil }, set: { if !$0 { testResult = nil } })) {
            Button("好", role: .cancel) { testResult = nil }
        } message: {
            Text(testResult ?? "")
        }
    }

    private func testConnection() {
        guard !testing else { return }
        testing = true
        Task {
            defer { testing = false }
            do {
                let j = try await auth.json("/api/auth/status")
                let ok = (j["ok"] as? Bool) ?? false
                testResult = ok ? "✅ 连接正常，服务器：\(shortServer)" : "⚠️ 服务器响应异常"
            } catch {
                testResult = "❌ 无法连接：\(shortServer)"
            }
        }
    }

    private var shortServer: String {
        auth.serverURL
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
    }
}

// MARK: - 服务器地址修改

struct ServerSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var server = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("服务器地址")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Text("修改后需重新登录")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 4)

            TextField("192.168.0.40:8080", text: $server)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.top, 14)

            Button {
                var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.hasPrefix("http") { s = "http://" + s }
                auth.serverURL = s
                UserDefaults.standard.set(s, forKey: "qingliao_server")
                saved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    auth.logout()
                }
            } label: {
                Text("保存并重新登录")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if saved {
                Text("已保存，正在返回登录...")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .onAppear {
            server = auth.serverURL.replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
        }
    }
}

// MARK: - 修改密码

struct PasswordSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var result: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("修改密码")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            SecureField("当前密码", text: $oldPassword)
                .font(.system(size: 14))
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.top, 14)

            SecureField("新密码", text: $newPassword)
                .font(.system(size: 14))
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.top, 10)

            Button {
                changePassword()
            } label: {
                Text(busy ? "提交中..." : "确认修改")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if let r = result {
                Text(r)
                    .font(.system(size: 12))
                    .foregroundStyle(r.contains("成功") ? Color.green : Color.red)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
    }

    private func changePassword() {
        guard !oldPassword.isEmpty, !newPassword.isEmpty, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let j = try await auth.json("/api/auth/change-password", method: "POST", body: [
                    "old": oldPassword, "new": newPassword
                ])
                if (j["ok"] as? Bool) ?? false {
                    result = "✅ 修改成功，请重新登录"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        auth.logout()
                    }
                } else {
                    result = "⚠️ " + ((j["error"] as? String) ?? "修改失败")
                }
            } catch {
                result = "❌ 修改失败，请检查当前密码"
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 5)
    }
}

struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil
    var chevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(Rectangle())
    }
}
