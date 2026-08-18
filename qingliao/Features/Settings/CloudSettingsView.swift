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
    // v3.0.1 fix：Dock 开关 key 用本地真实 key qingliao_hide_dock（原 qingliao_show_dock 不存在→开关无效）
    // 语义与本地一致：hideDock=true = 隐藏 Dock
    @AppStorage("qingliao_hide_dock") private var hideDock = false
    @AppStorage("qingliao_font_scale") private var fontScale = 1.0
    @AppStorage("qingliao_ai_line_spacing") private var aiLineSpacing = 1.0
    // v3.0.1：Siri 发光自定义参数（与本地 AI 外观设置一致，4 项）
    @AppStorage("qingliao_siri_glow_brightness") private var glowBrightness = 1.0
    @AppStorage("qingliao_siri_glow_freq") private var glowFreq = 2.2
    @AppStorage("qingliao_siri_glow_amp") private var glowAmp = 0.18
    @AppStorage("qingliao_siri_glow_width") private var glowWidth = 22.0

    var body: some View {
        NavigationStack {
            Form {
                Section("交互") {
                    Toggle("智能球输入", isOn: $ballInput)
                    Toggle("Dock 栏", isOn: $hideDock)
                        // v3.0.1：与本地 AI 一致，联动 DockVisibility 立即生效
                        .onChange(of: hideDock) { _, on in
                            if on {
                                DockVisibility.shared.forceHidden = true
                                DockVisibility.shared.hidden = true
                            } else {
                                DockVisibility.shared.forceHidden = false
                                DockVisibility.shared.reset()
                            }
                        }
                    // v2.0.46：隐藏 Dock 时输入框贴底（本地 ChatView 读取 hideDock），无额外项
                }
                Section("AI 回答发光") {
                    Toggle("Siri 边框发光", isOn: $siriGlow)
                    if siriGlow {
                        sliderRow("亮度", value: $glowBrightness, range: 0.2...1.5, format: "%.0f%%", suffix: { String(format: "%.0f%%", $0 * 100) })
                        sliderRow("呼吸频率", value: $glowFreq, range: 0.5...6.0, format: "%.1f", suffix: { String(format: "%.1f", $0) })
                        sliderRow("呼吸幅度", value: $glowAmp, range: 0...0.4, format: "%.2f", suffix: { String(format: "%.2f", $0) })
                        sliderRow("光带范围", value: $glowWidth, range: 10...44, format: "%.0fpt", suffix: { String(format: "%.0fpt", $0) })
                    }
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
                    HStack {
                        Text("AI 输出行高")
                        Spacer()
                        Text(String(format: "%.1f", aiLineSpacing))
                            .foregroundStyle(.secondary)
                        Stepper("", value: $aiLineSpacing, in: 0...6, step: 0.5)
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

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           format: String, suffix: @escaping (Double) -> String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range).tint(Color.accentColor)
            Text(suffix(value.wrappedValue)).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
