import SwiftUI

// MARK: - 设置页（iOS 设置风格分组列表，全部功能行可用）

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @AppStorage("qingliao_appearance") private var appearance = "system"   // dark/light/system（默认跟随系统）

    @State private var showServerSheet = false
    @State private var showPasswordSheet = false
    @State private var showFiles = false
    @State private var showTasks = false
    @State private var showLogs = false
    @State private var showAppearanceOptions = false
    @State private var scrollPos = ScrollPosition()
    @State private var showSessionLocSheet = false
    @State private var sessionLoc = ""   // 服务器端会话存储路径（GET /api/sessions/location）
    @State private var showModelSheet = false
    @State private var showAbout = false
    @State private var showSecrets = false
    @State private var secretCount = 0
    @State private var showHASettings = false
    @State private var haAddress = ""
    @State private var testResult: String?
    @State private var testing = false

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
                        SettingRow(icon: "cpu.fill", iconColor: .orange, title: "模型管理", value: currentModel, chevron: true)
                            .onTapGesture { showModelSheet = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "network", iconColor: .blue, title: "测试连接", value: testing ? "检测中..." : nil, chevron: !testing)
                            .onTapGesture { testConnection() }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "tray.full.fill", iconColor: .teal, title: "会话存储位置", value: sessionLocShort, chevron: true)
                            .onTapGesture { showSessionLocSheet = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "house.fill", iconColor: .purple, title: "HA 设置", value: haAddress.isEmpty ? nil : "\(haAddress)", chevron: true)
                            .onTapGesture { showHASettings = true }
                    }
                    .glassListCard()

                    // 功能
                    SectionHeader("功能")
                    VStack(spacing: 0) {
                        SettingRow(icon: "key.fill", iconColor: .teal, title: "密码管理", value: "\(secretCount) 条凭据", chevron: true)
                            .onTapGesture { showSecrets = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "folder.fill", iconColor: .indigo, title: "文件管理", chevron: true)
                            .onTapGesture { showFiles = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "clock.badge.fill", iconColor: .red, title: "定时任务", chevron: true)
                            .onTapGesture { showTasks = true }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "doc.text.fill", iconColor: .orange, title: "日志", chevron: true)
                            .onTapGesture { showLogs = true }
                    }
                    .glassListCard()

                    // 其他
                    SectionHeader("其他")
                    VStack(spacing: 0) {
                        SettingRow(icon: "circle.lefthalf.filled", iconColor: .purple, title: "外观", value: appearanceName, chevron: true)
                            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showAppearanceOptions.toggle() } }
                        if showAppearanceOptions {
                            // 内联三选（非弹窗）
                            HStack(spacing: 8) {
                                appearanceOption("深色", value: "dark")
                                appearanceOption("浅色", value: "light")
                                appearanceOption("跟随系统", value: "system")
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "info.circle.fill", iconColor: .gray, title: "关于轻聊", value: "2.0", chevron: true)
                            .onTapGesture { showAbout = true }
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
            .scrollPosition($scrollPos)
            .onChange(of: scrollPos.y) { _, y in
                DockVisibility.shared.update(y ?? 0)
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
        .sheet(isPresented: $showSessionLocSheet) {
            SessionLocSheet(currentPath: sessionLoc)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showModelSheet) {
            ModelSheet(current: currentModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSecrets) {
            SecretsView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showHASettings) {
            HASettingsSheet()
                .presentationDetents([.medium])
        }
        .task {
            if let j = try? await auth.json("/api/secrets") {
                secretCount = (j["secrets"] as? [Any])?.count ?? 0
            }
            if let j = try? await auth.json("/api/ha/config") {
                haAddress = j["address"] as? String ?? ""
            }
        }
        .alert("测试连接", isPresented: Binding(get: { testResult != nil }, set: { if !$0 { testResult = nil } })) {
            Button("好", role: .cancel) { testResult = nil }
        } message: {
            Text(testResult ?? "")
        }
        .task {
            // 拉取服务器端会话存储位置
            if let j = try? await auth.json("/api/sessions/location") {
                sessionLoc = j["path"] as? String ?? ""
            }
        }
    }

    private func appearanceOption(_ name: String, value: String) -> some View {
        Button {
            appearance = value
            withAnimation(.easeOut(duration: 0.2)) { showAppearanceOptions = false }
        } label: {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(appearance == value ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appearance == value ? Color.accentColor : Color(uiColor: .systemGray5))
                )
        }
        .buttonStyle(.plain)
    }

    private var appearanceName: String {
        switch appearance {
        case "light": return "浅色"
        case "system": return "跟随系统"
        default: return "深色"
        }
    }

    /// 会话存储位置短显（取路径后两段）
    private var sessionLocShort: String {
        let parts = sessionLoc.split(separator: "/").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "…/" + parts.suffix(2).joined(separator: "/")
        }
        return sessionLoc.isEmpty ? "默认" : sessionLoc
    }

    /// 当前默认模型（UserDefaults）
    private var currentModel: String {
        UserDefaults.standard.string(forKey: "qingliao_model") ?? "deepseek-v4-flash"
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

// MARK: - 会话存储位置设置（NAS 目录，服务器持久化）

struct SessionLocSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let currentPath: String
    @State private var path = ""
    @State private var result: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("会话存储位置")
                .font(.system(size: 17, weight: .bold))
            Text("设置 NAS 上存储会话记录的目录（需为服务器可写路径）")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("如 /volume1/docker/轻聊数据/sessions", text: $path)
                .font(.system(size: 14, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let result {
                Text(result)
                    .font(.system(size: 12))
                    .foregroundStyle(result.hasPrefix("✅") ? Color.green : Color.red)
            }
            Button {
                save()
            } label: {
                HStack {
                    Spacer()
                    if saving { ProgressView().tint(.white) } else { Text("保存") }
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(saving)
            Spacer()
        }
        .padding(20)
        .onAppear { path = currentPath }
    }

    private func save() {
        saving = true
        result = nil
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { saving = false }
            do {
                let j = try await auth.json("/api/sessions/location", method: "POST", body: ["path": p])
                if (j["ok"] as? Bool) == true {
                    result = "✅ 已保存：" + (j["path"] as? String ?? p)
                } else {
                    result = "❌ " + ((j["error"] as? String) ?? "保存失败")
                }
            } catch {
                result = "❌ 请求失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 模型管理（复刻 PWA/OpenCode Go 面板：分组 + 设为当前 + 同步列表）

struct ModelSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let current: String
    @State private var selected = ""
    @State private var syncing = false
    @State private var syncResult: String?
    // 服务器同步的模型（分组展示）
    @State private var stepfunModels: [String] = []
    @State private var deepseekModels: [String] = []

    /// opencode 本地预置（官方 /v1/models 端点 403 不开放，本地维护）
    private let localModels: [(String, String)] = [
        ("deepseek-v4-flash", "DeepSeek V4 Flash"),
        ("deepseek-v4-flash-free", "DeepSeek V4 Flash Free"),
        ("deepseek-v4-pro", "DeepSeek V4 Pro"),
        ("kimi-k3", "Kimi K3"),
        ("kimi-k2.7-code", "Kimi K2.7 Code"),
        ("kimi-k2.6", "Kimi K2.6"),
        ("kimi-k2.5", "Kimi K2.5"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部：🧠 模型管理 + 刷新 + 同步列表 + 在线状态
            HStack(spacing: 8) {
                Text("🧠").font(.system(size: 18))
                Text("模型管理").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { syncList() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Button { syncList() } label: {
                    Text("同步列表")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // 在线状态 + 同步结果
            HStack(spacing: 5) {
                Circle().fill(syncing ? Color.orange : Color.green).frame(width: 7, height: 7)
                Text(syncing ? "同步中..." : "OpenCode Go 在线")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let syncResult {
                Text(syncResult)
                    .font(.system(size: 11))
                    .foregroundStyle(syncResult.hasPrefix("✅") ? Color.green : Color.orange)
            }
            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    groupSection("opencode", models: localModels.map { ($0.0, $0.1, "opencode") })
                    if !deepseekModels.isEmpty {
                        groupSection("deepseek", models: deepseekModels.map { ($0, $0, "deepseek") })
                    }
                    if !stepfunModels.isEmpty {
                        groupSection("stepfun", models: stepfunModels.map { ($0, $0, "stepfun") })
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(18)
        .onAppear {
            selected = current
            // 恢复上次同步的模型（UserDefaults 持久化，无需每次点同步）
            if let s = UserDefaults.standard.array(forKey: "qingliao_models_stepfun") as? [String] {
                stepfunModels = s
            }
            if let d = UserDefaults.standard.array(forKey: "qingliao_models_deepseek") as? [String] {
                deepseekModels = d
            }
        }
    }

    /// 分组标题 + 模型行
    private func groupSection(_ group: String, models: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(models, id: \.0) { m in
                modelRow(id: m.0, name: m.1, provider: m.2)
            }
        }
    }

    private func modelRow(id: String, name: String, provider: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(id)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected == id ? Color.accentColor : Color.primary)
                Text(name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected == id {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                    Text("当前").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            } else {
                Button {
                    setModel(id, provider: provider)
                } label: {
                    Text("设为当前")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(selected == id ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                              lineWidth: 0.8)
        )
    }

    private func setModel(_ id: String, provider: String) {
        selected = id
        UserDefaults.standard.set(id, forKey: "qingliao_model")
        UserDefaults.standard.set(provider, forKey: "qingliao_provider")
    }

    /// 同步模型列表：stepfun/deepseek 官方端点可同步，opencode 保持本地预置
    private func syncList() {
        guard !syncing else { return }
        syncing = true
        syncResult = nil
        Task {
            let s = await fetchModels("stepfun")
            let d = await fetchModels("deepseek")
            if let s {
                stepfunModels = s
                UserDefaults.standard.set(s, forKey: "qingliao_models_stepfun")
            }
            if let d {
                deepseekModels = d
                UserDefaults.standard.set(d, forKey: "qingliao_models_deepseek")
            }
            syncResult = "✅ 已同步（stepfun \(stepfunModels.count) / deepseek \(deepseekModels.count)）"
            syncing = false
        }
    }

    private func fetchModels(_ provider: String) async -> [String]? {
        guard let j = try? await auth.json("/api/stream/sync-models?provider=\(provider)"),
              (j["ok"] as? Bool) == true,
              let list = j["models"] as? [String] else { return nil }
        return list
    }
}

// MARK: - 关于轻聊（软件介绍页）

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            // v2.0.34：关于页换新图标（淡青底微笑气泡，与 AppIcon 同款）
            Image("AboutLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text("轻聊")
                .font(.system(size: 22, weight: .bold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 8) {
                aboutRow("简介", "连接自家 Hermes Agent Server 的 AI 智能助手，支持多模型、NAS 控制、文件管理与智能家居。")
                aboutRow("模型", "DeepSeek V4 / Kimi / StepFun 多模型聚合（OpenCode Go）")
                aboutRow("功能", "流式对话 · 语音输入 · 会话同步 · NAS 面板 · 智能家居 · 文件管理 · 定时任务")
                aboutRow("网络", "iOS 27 蜂窝直连优化 + Safari Relay 兜底")
                aboutRow("架构", "SwiftUI 原生 · Hermes Agent · 自建 NAS 后端")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 24)

            Spacer()
            Text("Nous Research · Hermes Agent")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .padding(.top, 22)
    }

    private func aboutRow(_ title: String, _ content: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}
