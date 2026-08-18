import SwiftUI

// MARK: - v3.0 云端模式设置页：只保留云端相关（模型厂商/外观/关于），数据存 App 本地

struct CloudSettingsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var config = CloudConfig.shared
    @State private var showAddSheet = false
    @State private var showAppearance = false
    @State private var showAbout = false
    @State private var confirmLogout = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "设置")
            ScrollView {
                VStack(spacing: 0) {
                    // 云端模型
                    SectionHeader("云端模型")
                    VStack(spacing: 0) {
                        ForEach(config.providers) { p in
                            HStack(spacing: 12) {
                                Image(systemName: "cube.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name)
                                        .font(.system(size: 14, weight: .medium))
                                    Text("\(p.model) · \(p.baseURL)")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if config.activeProviderID == p.providerID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Button {
                                        config.activeProviderID = p.providerID
                                    } label: {
                                        Text("选用")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            if p.providerID != config.providers.last?.providerID {
                                Divider().padding(.leading, 52)
                            }
                        }
                        Divider().padding(.leading, 52)
                        SettingRow(icon: "plus.circle.fill", iconColor: .blue, title: "添加/编辑厂商", chevron: true)
                            .onTapGesture { showAddSheet = true }
                    }
                    .glassListCard()

                    // 外观
                    SectionHeader("外观")
                    VStack(spacing: 0) {
                        SettingRow(icon: "paintbrush.fill", iconColor: .pink, title: "外观设置", value: nil, chevron: true)
                            .onTapGesture { showAppearance = true }
                    }
                    .glassListCard()

                    // 关于
                    SectionHeader("关于")
                    VStack(spacing: 0) {
                        SettingRow(icon: "info.circle.fill", iconColor: .gray, title: "关于轻聊", value: "v3.0.0", chevron: true)
                            .onTapGesture { showAbout = true }
                    }
                    .glassListCard()

                    // 退出登录（切换模式/账号）
                    SectionHeader("")
                    Button {
                        confirmLogout = true
                    } label: {
                        Text("退出登录（返回模式选择）")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
                        Button("退出登录", role: .destructive) {
                            auth.logout()
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("退出后回到登录页，可切换本地 AI / 云端 AI 模式。云端配置（API Key）仍保留在手机本地。")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CloudProviderSheet(existing: config.providers) { newConfig in
                config.saveProvider(newConfig)
                config.activeProviderID = newConfig.providerID
            }
        }
        .sheet(isPresented: $showAppearance) {
            AppearanceSheet()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
}

// MARK: - 云端模式外观设置（复用本地外观参数，仅保留外观相关项）

struct AppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("qingliao_siri_glow") private var siriGlow = false
    @AppStorage("qingliao_ball_input") private var ballInput = true
    @AppStorage("qingliao_show_dock") private var showDock = true
    @AppStorage("qingliao_font_scale") private var fontScale = 1.0

    var body: some View {
        NavigationStack {
            Form {
                Section("交互") {
                    Toggle("智能球输入", isOn: $ballInput)
                    Toggle("Siri 发光", isOn: $siriGlow)
                    Toggle("显示底部 Dock", isOn: $showDock)
                }
                Section("字体") {
                    HStack {
                        Text("字体大小")
                        Spacer()
                        Text(String(format: "%.0f%%", fontScale * 100))
                            .foregroundStyle(.secondary)
                        Stepper("", value: $fontScale, in: 0.85...1.4, step: 0.05)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle("外观设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
