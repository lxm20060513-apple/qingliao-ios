import SwiftUI
import LocalAuthentication

// MARK: - 设置页（iOS 设置风格分组列表，全部功能行可用）

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @AppStorage("qingliao_appearance") private var appearance = "system"   // dark/light/system（默认跟随系统）

    // v2.0.83c：连接设置二级页（服务器地址/测试连接/会话存储位置收进二级）
    @State private var showConnSettings = false
    @State private var showPasswordSheet = false
    @State private var showSecrets = false
    // v2.0.81：知识库页面
    @State private var showKB = false
    // v2.0.87：AI 记忆
    @State private var showMemory = false
    @State private var memoryCount = 0
    @State private var showTasks = false
    @State private var showLogs = false
    @State private var showAppearanceOptions = false
    @State private var showAppearance = false   // v3.0.4：外观弹窗（与云端统一）
    @State private var scrollPos = ScrollPosition()
    @State private var showModelSheet = false
    @State private var showBotManage = false   // v3.0.7：Bot 管理
    @State private var showWechatChannel = false   // v3.0.19：微信窗通道模型设置
    @State private var showAbout = false
    @State private var confirmLogout = false   // v3.0.5 review fix：退出登录二次确认（与云端一致）
    @State private var secretCount = 0
    @State private var showHASettings = false
    @State private var haAddress = ""
    // v3.0.17：聊天字体大小从一级菜单移除（外观二级菜单持有），fontSize 声明一并清理
    // v3.0.9：外观下天气城市已移除（天气城市设定在看板 WeatherBadge 点按处），相关状态一并清理
    // v2.0.101：Agent 使用说明内联展开
    @State private var showAgentHelp = false
    // v2.0.105：Agent 关键词管理弹窗
    @State private var showAgentKeywords = false
    // v2.0.113：Agent 记忆弹窗 + 计数
    @State private var showAgentMemory = false
    @State private var agentRuleCount = 0
    // v3.0.20：Agent 模型自定义（独立于主模型，可单独指定 Agent 使用的模型）
    @State private var showAgentModelSheet = false
    @AppStorage("qingliao_agent_model") private var agentModel = ""
    @AppStorage("qingliao_agent_provider") private var agentProvider = ""
    // v2.0.116：执行历史弹窗
    @State private var showHistory = false
    // v2.0.117：本地模型（Ollama 断网兜底）
    @AppStorage("qingliao_local_model") private var localModelOn = false
    @State private var localStatusText = "未开启"
    @State private var localUpdateText = "断网兜底用本地模型"
    @State private var localChecking = false
    // v2.0.118：本地模型管理弹窗
    @State private var showLocalModels = false
    // v3.0.10：视觉模型配置弹窗（已移至模型管理弹窗内）
    // v2.0.113：微信推送开关（同步后端 push_settings.json）
    @AppStorage("qingliao_push_weixin") private var pushWeixin = true
    // v2.0.87ax：输入框流光光效开关
    @AppStorage("qingliao_input_glow") private var glowOn = true
    // v2.0.87bb：Siri 边框发光开关
    @AppStorage("qingliao_siri_glow") private var siriGlowOn = true
    // v2.0.90a：Siri 动效自定义参数（默认 = v2.0.87bn 定稿效果）
    @AppStorage("qingliao_siri_glow_brightness") private var glowBrightness = 1.0
    @AppStorage("qingliao_siri_glow_freq") private var glowFreq = 2.2
    @AppStorage("qingliao_siri_glow_amp") private var glowAmp = 0.18
    @AppStorage("qingliao_siri_glow_width") private var glowWidth = 22.0
    // v2.0.88：Face ID 登录开关（关闭后删除 Keychain 凭据，登录页不再显示快捷按钮）
    @AppStorage("qingliao_faceid_login") private var faceIDLogin = true
    @State private var faceIDAuthFailed = false   // v2.0.89f：开关打开时系统授权失败提示
    // v2.0.92：App 锁开关（启动时 Face ID 验证）
    @AppStorage("qingliao_app_lock") private var appLockOn = false
    @State private var appLockAuthFailed = false
    // v2.0.128：AI 输出行高（0-6 步进 0.5，默认 1.0 = 紧凑；滑条控制）
    @AppStorage("qingliao_ai_line_spacing") private var aiLineSpacing = 1.0
    @State private var showLineSpacingOptions = false
    // v2.0.129：Siri 圆球输入（默认开——输入框区显示多彩圆球，单击展开 / 长按语音转文字）
    @AppStorage("qingliao_ball_input") private var ballInput = true
    // v2.0.45：隐藏 Dock 栏开关
    @AppStorage("qingliao_hide_dock") private var hideDock = false
    // v2.0.98：Agent 智能回复开关（关闭后请求不带 agent 能力，走普通 LLM 回复）
    @AppStorage("qingliao_agent_enabled") private var agentOn = true

    // MARK: - Section 计算属性（body 瘦身：500 行 → 8 个独立段，SwiftUI diff 只遍历变化段）

    @ViewBuilder private var accountSection: some View {
        SectionHeader("账号与安全")
        VStack(spacing: 0) {
            SettingRow(icon: "person.crop.circle.fill", iconColor: .blue, title: auth.username, value: "已登录")
            Divider().padding(.leading, 52)
            SettingRow(icon: "key.horizontal.fill", iconColor: .gray, title: "修改密码", chevron: true)
                .onTapGesture { showPasswordSheet = true }
            Divider().padding(.leading, 52)
            toggleRow(icon: "faceid", iconColor: .blue, title: "Face ID 登录", isOn: $faceIDLogin)
                .onChange(of: faceIDLogin) { _, on in
                    if on { requestFaceIDAuth() } else { FaceIDStore.clear() }
                }
                .alert("Face ID 未授权", isPresented: $faceIDAuthFailed) {
                    Button("好的", role: .cancel) {}
                } message: {
                    Text("未通过系统 Face ID 验证，登录页快捷登录不可用。")
                }
            Divider().padding(.leading, 52)
            toggleRow(icon: "lock.fill", iconColor: .green, title: "App 锁", isOn: $appLockOn)
                .onChange(of: appLockOn) { _, on in
                    if on { requestAppLockAuth() }
                }
                .alert("Face ID 未授权", isPresented: $appLockAuthFailed) {
                    Button("好的", role: .cancel) {}
                } message: {
                    Text("未通过系统 Face ID 验证，App 锁不可用。")
                }
        }
        .glassListCard()
    }

    @ViewBuilder private var connectionSection: some View {
        SectionHeader("连接与模型")
        VStack(spacing: 0) {
            SettingRow(icon: "globe.asia.australia.fill", iconColor: .green, title: "连接设置", chevron: true)
                .onTapGesture { showConnSettings = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "cpu.fill", iconColor: .orange, title: "模型管理", value: currentModel, chevron: true)
                .onTapGesture { showModelSheet = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "person.2.crop.square.stack.fill", iconColor: .teal, title: "Bot 管理",
                       value: CloudConfig.shared.isCloudMode ? "仅本地模式" : nil, chevron: true)
                .onTapGesture { showBotManage = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "bubble.left.and.bubble.right.fill", iconColor: .blue,
                       title: "微信通道模型", value: wechatChannelModel, chevron: true)
                .onTapGesture { showWechatChannel = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "house.fill", iconColor: .purple, title: "HA 设置", chevron: true)
                .onTapGesture { showHASettings = true }
            Divider().padding(.leading, 52)
            localModelToggle
        }
        .glassListCard()
    }

    @ViewBuilder private var localModelToggle: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("本地模型").font(.system(size: 14, weight: .medium))
                Text(localStatusText).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $localModelOn).labelsHidden().scaleEffect(0.8).tint(.green)
                .onChange(of: localModelOn) { _, new in
                    Task {
                        _ = try? await auth.json("/api/local/toggle", method: "POST", body: ["on": new])
                        await loadLocalStatus()
                    }
                }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        if localModelOn {
            Divider().padding(.leading, 52)
            SettingRow(icon: "shippingbox.fill", iconColor: .indigo, title: "管理模型",
                       value: "已装列表 / 拉取新模型", chevron: true)
                .onTapGesture { showLocalModels = true }
            Divider().padding(.leading, 52)
            Button { Task { await checkLocalUpdate() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.teal, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("检查模型更新").font(.system(size: 14, weight: .medium))
                        Text(localUpdateText).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if localChecking { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }

    @ViewBuilder private var aiSection: some View {
        SectionHeader("AI 智能")
        VStack(spacing: 0) {
            SettingRow(icon: "books.vertical.fill", iconColor: .green, title: "知识库", value: "文档检索问答", chevron: true)
                .onTapGesture { showKB = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "brain.head.profile", iconColor: .pink, title: "AI 记忆", value: "\(memoryCount) 条", chevron: true)
                .onTapGesture { showMemory = true }
            Divider().padding(.leading, 52)
            toggleRow(icon: "message.badge.filled.fill", iconColor: .green,
                      title: "微信推送", subtitle: "自动化执行结果推送到微信", isOn: $pushWeixin)
                .onChange(of: pushWeixin) { _, new in
                    Task { _ = try? await auth.json("/api/push/settings", method: "POST", body: ["pushWeixin": new]) }
                }
        }
        .glassListCard()
    }

    @ViewBuilder private var dataSection: some View {
        SectionHeader("数据与自动化")
        VStack(spacing: 0) {
            SettingRow(icon: "key.fill", iconColor: .teal, title: "密码管理", value: "\(secretCount) 条凭据", chevron: true)
                .onTapGesture { showSecrets = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "clock.badge.fill", iconColor: .red, title: "定时任务", chevron: true)
                .onTapGesture { showTasks = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "clock.arrow.circlepath", iconColor: .orange, title: "执行历史",
                       value: "自动化/场景执行记录", chevron: true)
                .onTapGesture { showHistory = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "doc.text.fill", iconColor: .orange, title: "日志", chevron: true)
                .onTapGesture { showLogs = true }
        }
        .glassListCard()
    }

    @ViewBuilder private var agentSection: some View {
        SectionHeader("Agent 设置")
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(LinearGradient(colors: [.blue, .indigo, .pink],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent 智能回复").font(.system(size: 15)).foregroundStyle(.primary)
                    Text(agentOn ? "已开启：查磁盘/内存/控制设备等直接调用工具" : "已关闭：所有对话走普通 AI 回复")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $agentOn).labelsHidden().scaleEffect(0.8).tint(.green)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            // v3.0.20：Agent 模型自定义（可单独指定 Agent 使用的模型，不依赖主模型）
            Divider().padding(.leading, 52)
            SettingRow(icon: "cpu.fill", iconColor: .indigo, title: "Agent 模型",
                       value: agentModel.isEmpty ? "跟随主模型" : agentModel, chevron: true)
                .onTapGesture { showAgentModelSheet = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "questionmark.circle.fill", iconColor: .gray, title: "使用说明", chevron: false)
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showAgentHelp.toggle() } }
            if showAgentHelp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent 回复 = 直连模型 + NAS 本地工具，不经 Hermes。")
                    Text("▸ 直接问：查磁盘/内存/温度、控制设备、执行场景，自动调用工具回复")
                    Text("▸ 记忆规则：说「以后XX都用agent」，下次同类问题直接 Agent 处理")
                    Text("▸ 复杂任务（联网搜索/写脚本/操作文件）自动转交 Hermes 执行")
                    Text("▸ 普通聊天走 Hermes（带 AI 记忆）；Agent 只参考轻聊记忆与规则")
                    Text("▸ 关闭开关后：所有对话走普通 AI 回复")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
            Divider().padding(.leading, 52)
            SettingRow(icon: "text.badge.plus", iconColor: .orange, title: "Agent 关键词", value: "分流匹配词管理", chevron: true)
                .onTapGesture { showAgentKeywords = true }
            Divider().padding(.leading, 52)
            SettingRow(icon: "brain.head.profile", iconColor: .purple, title: "Agent 记忆",
                       value: agentRuleCount > 0 ? "\(agentRuleCount) 条规则" : "暂无", chevron: true)
                .onTapGesture { showAgentMemory = true }
        }
        .glassListCard()
    }

    @ViewBuilder private var appearanceSection: some View {
        SectionHeader("外观与显示")
        VStack(spacing: 0) {
            SettingRow(icon: "circle.lefthalf.filled", iconColor: .purple, title: "外观", value: appearanceName, chevron: true)
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showAppearance = true } }
            if showAppearanceOptions {
                HStack(spacing: 8) {
                    appearanceOption("深色", value: "dark")
                    appearanceOption("浅色", value: "light")
                    appearanceOption("跟随系统", value: "system")
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
                Divider().padding(.leading, 52)
                toggleRow(icon: "rectangle.bottomthird.inset.filled", iconColor: .teal, title: "Dock 栏设置", isOn: $hideDock)
                    .onChange(of: hideDock) { _, on in
                        if on {
                            DockVisibility.shared.forceHidden = true; DockVisibility.shared.hidden = true
                        } else {
                            DockVisibility.shared.forceHidden = false; DockVisibility.shared.reset()
                        }
                    }
                Divider().padding(.leading, 52)
                toggleRow(icon: "waveform", iconColor: .purple, title: "输入框流光光效", isOn: $glowOn)
                Divider().padding(.leading, 52)
                toggleRow(icon: "sparkles.rectangle.stack", iconColor: .indigo, title: "Siri 边框发光", isOn: $siriGlowOn)
                if siriGlowOn {
                    siriGlowSliders
                }
                Divider().padding(.leading, 52)
                SettingRow(icon: "text.line.first.and.arrowtriangle.forward", iconColor: .indigo,
                           title: "AI 输出行高", value: String(format: "%.1f", aiLineSpacing))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showLineSpacingOptions.toggle() } }
                if showLineSpacingOptions {
                    HStack(spacing: 10) {
                        Text("紧凑").font(.system(size: 12)).foregroundStyle(.secondary)
                        Slider(value: $aiLineSpacing, in: 0...6, step: 0.5).tint(Color.accentColor)
                        Text("宽松").font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
                Divider().padding(.leading, 52)
                toggleRow(icon: "circle.circle.fill", iconColor: .accentColor, title: "智能球", isOn: $ballInput)
            }
        }
        .glassListCard()
    }

    @ViewBuilder private var siriGlowSliders: some View {
        Divider().padding(.leading, 52)
        glowSlider("亮度", value: $glowBrightness, range: 0.2...1.5, format: "%.0f%%")
        glowSlider("呼吸频率", value: $glowFreq, range: 0.5...6.0, format: "%.1f")
        glowSlider("呼吸幅度", value: $glowAmp, range: 0...0.4, format: "%.2f")
        glowSlider("光带范围", value: $glowWidth, range: 10...44, format: "%.0fpt")
            .padding(.bottom, 6)
    }

    @ViewBuilder private var aboutSection: some View {
        SectionHeader("关于")
        VStack(spacing: 0) {
            SettingRow(icon: "info.circle.fill", iconColor: .gray, title: "关于轻聊", chevron: true)
                .onTapGesture { showAbout = true }
        }
        .glassListCard()
    }

    @ViewBuilder private var logoutButton: some View {
        SectionHeader("")
        Button {
            confirmLogout = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("退出登录")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 40).padding(.vertical, 13)
            .background(Color.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .confirmationDialog("退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { auth.logout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后回到登录页，可切换本地 AI / 云端 AI 模式。")
        }
        .padding(.top, 2)
    }

    // MARK: - 共用组件（toggle 行 / Siri 滑条）

    private func toggleRow(icon: String, iconColor: Color, title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            if let subtitle {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            } else {
                Text(title).font(.system(size: 15)).foregroundStyle(.primary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().scaleEffect(0.8).tint(.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func glowSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Slider(value: value, in: range).tint(Color.accentColor)
            Text(String(format: format, value.wrappedValue)).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "设置")
            ScrollView {
                VStack(spacing: 0) {
                    accountSection
                    connectionSection
                    aiSection
                    dataSection
                    agentSection
                    appearanceSection
                    aboutSection
                    logoutButton
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
            .scrollPosition($scrollPos)
        }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAppearance) {
            // v3.0.4：外观弹窗（与云端共用同一组件，样式统一）
            AppearanceSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTasks) {
            TasksView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLogs) {
            LogsView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showConnSettings) {
            ConnSettingsView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showModelSheet) {
            ModelSheet(current: currentModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showWechatChannel) {
            WechatChannelSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBotManage) {
            // v3.0.7：Bot 管理（云端模式下 BotStore 拉取会失败，入口标注「仅本地模式」）
            BotManageSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSecrets) {
            SecretsView()
                .presentationDetents([.medium, .large])
        }
        // v2.0.81：知识库
        .sheet(isPresented: $showKB) {
            KBView()
                .presentationDetents([.medium, .large])
        }
        // v2.0.87：AI 记忆
        .sheet(isPresented: $showMemory) {
            MemoryView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHASettings) {
            HASettingsSheet()
                .presentationDetents([.medium])
        }
        // v2.0.105：Agent 关键词管理
        .sheet(isPresented: $showAgentKeywords) {
            AgentKeywordsSheet()
        }
        // v2.0.113：Agent 记忆弹窗（同 AI 记忆样式）
        .sheet(isPresented: $showAgentMemory) {
            AgentMemorySheet()
        }
        // v3.0.20：Agent 模型选择弹窗
        .sheet(isPresented: $showAgentModelSheet) {
            AgentModelSheet()
                .presentationDetents([.medium, .large])
        }
        // v2.0.116：执行历史弹窗
        .sheet(isPresented: $showHistory) {
            HistorySheet()
        }
        // v2.0.118：本地模型管理弹窗
        .sheet(isPresented: $showLocalModels) {
            LocalModelsSheet()
        }
        // v2.0.102：切回设置页刷新计数（密码管理/记忆增删后行尾数字即时更新，原只有 .task 首刷）
        .onAppear { Task { await loadCounts() } }
        .task { await loadCounts() }
    }

    /// v2.0.117：加载本地模型状态（容器 + 已装模型）
    private func loadLocalStatus() async {
        if let j = try? await auth.json("/api/local/status") {
            let up = (j["container"] as? String) == "up"
            let models = (j["models"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "" }
            if up {
                localStatusText = "运行中" + (models.isEmpty ? "" : " · " + models.prefix(2).joined(separator: " / "))
            } else {
                localStatusText = "已停止（点开关开启）"
            }
        }
    }

    /// v2.0.117：检查模型更新
    private func checkLocalUpdate() async {
        guard !localChecking else { return }
        localChecking = true
        defer { localChecking = false }
        if let j = try? await auth.json("/api/local/check-update") {
            localUpdateText = (j["message"] as? String) ?? "检查完成"
        } else {
            localUpdateText = "检查失败，请稍后重试"
        }
    }

    /// v2.0.102：加载凭据/记忆计数（设置页行尾显示）
    private func loadCounts() async {
        if let j = try? await auth.json("/api/secrets") {
            secretCount = (j["secrets"] as? [Any])?.count ?? 0
        }
        if let j = try? await auth.json("/api/memory/list") {
            memoryCount = (j["entries"] as? [String] ?? []).count
        }
        // v2.0.113：同步微信推送开关（后端为准）
        if let j = try? await auth.json("/api/push/settings"),
           let v = j["pushWeixin"] as? Bool {
            pushWeixin = v
        }
        // v2.0.113：Agent 记忆条数（行尾数字）
        if let j = try? await auth.json("/api/agent/rules") {
            agentRuleCount = (j["rules"] as? [Any] ?? []).count
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

    /// 当前默认模型（UserDefaults）
    private var currentModel: String {
        UserDefaults.standard.string(forKey: "qingliao_model") ?? "deepseek-v4-flash"
    }

    // v3.0.19：微信通道当前模型（UserDefaults 缓存，进弹窗时刷新）
    private var wechatChannelModel: String {
        UserDefaults.standard.string(forKey: "qingliao_wechat_channel_model") ?? "跟随默认"
    }

    /// v2.0.89f：打开 Face ID 开关时立即申请系统权限（用户实测"点开关没有权限申请"）
    private func requestFaceIDAuth() {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            faceIDLogin = false   // 设备不支持/已被拒绝 → 回滚开关
            faceIDAuthFailed = true
            return
        }
        context.localizedReason = "用于登录页一键登录轻聊"
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "用于登录页一键登录轻聊") { success, error in
            DispatchQueue.main.async {
                if success { return }
                // v2.0.102：用户主动取消（userCancel）不算失败——保留开关不弹提示
                if let la = error as? LAError, la.code == .userCancel { return }
                // 拒绝/系统错误 → 回滚开关，提示去系统设置开启
                faceIDLogin = false
                faceIDAuthFailed = true
            }
        }
    }

    /// v2.0.92：打开 App 锁开关时申请权限（逻辑同 Face ID 登录）
    private func requestAppLockAuth() {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            appLockOn = false
            appLockAuthFailed = true
            return
        }
        context.localizedReason = "用于启动时解锁轻聊"
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "用于启动时解锁轻聊") { success, error in
            DispatchQueue.main.async {
                if success { return }
                // v2.0.102：用户主动取消不算失败——保留开关不弹提示
                if let la = error as? LAError, la.code == .userCancel { return }
                appLockOn = false
                appLockAuthFailed = true
            }
        }
    }
}

// MARK: - 服务器地址修改

struct ServerSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var server = ""
    @State private var saved = false
    @State private var validationError: String?

    /// 校验服务器地址格式（host:port 或 URL；端口 1-65535）
    private func validate(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "请输入服务器地址" }
        let stripped = s.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let parts = stripped.split(separator: ":")
        guard parts.count <= 2 else { return "格式错误，应为 host:port" }
        let host = String(parts[0]).trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return "主机名不能为空" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        if host.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "主机名含非法字符"
        }
        if parts.count == 2 {
            let portStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard let port = Int(portStr), port >= 1, port <= 65535 else {
                return "端口号须为 1-65535"
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("修改后需重新登录")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                TextField("server.example.com:8080", text: $server)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .onChange(of: server) { _, _ in validationError = nil }

                if let err = validationError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 4)
                }

                Button {
                    if let err = validate(server) {
                        validationError = err
                        return
                    }
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
        .navigationTitle("服务器地址")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear {
            server = auth.serverURL.replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
        }
        }
    }
}

// MARK: - 修改密码

struct PasswordSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""   // v2.0.83c：新密码二次确认
    @State private var result: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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

            // v2.0.83c：新密码二次确认（两次一致才可提交）
            SecureField("确认新密码", text: $confirmPassword)
                .font(.system(size: 14))
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.top, 10)
            if !confirmPassword.isEmpty && confirmPassword != newPassword {
                Text("两次输入的密码不一致")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
            }

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
        .navigationTitle("修改密码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        }
    }

    private func changePassword() {
        // v2.0.83c：新密码二次确认校验
        guard !oldPassword.isEmpty, !newPassword.isEmpty, !busy else { return }
        guard newPassword == confirmPassword else {
            result = "两次输入的密码不一致"
            return
        }
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
    // v2.0.87az：行尾开关（替代独立 Toggle 行，避免错位）
    var toggle: Binding<Bool>? = nil

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
            // v2.0.87az：行尾开关
            if let toggle {
                Toggle("", isOn: toggle)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .tint(.green)
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
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
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
        .navigationTitle("会话存储位置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear { path = currentPath }
        }
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

// MARK: - v3.0.35 provider 模型列表缓存（微信通道 / Agent / 模型管理共用同一份）
//
// 问题背景：WechatChannelSheet / AgentModelSheet 每次打开都从后端拉
// /api/stream/model-providers，失败时 try? 静默吞错 → 列表永远显示"正在加载模型列表…"。
// 方案：成功拉取结果写入 UserDefaults，打开时先显示缓存（免转圈），后台刷新成功后替换。

enum ModelProvidersCache {
    static let key = "qingliao_providers_cache"

    /// 读取缓存（无缓存或解析失败返回空）
    static func load() -> [(id: String, models: [String])] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            return (id, (d["models"] as? [String]) ?? [])
        }
    }

    /// 写缓存（空列表不覆盖旧缓存——防止后端临时故障把缓存刷空）
    static func save(_ providers: [(id: String, models: [String])]) {
        guard !providers.isEmpty else { return }
        let arr: [[String: Any]] = providers.map { ["id": $0.id, "models": $0.models] }
        if let data = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(data, forKey: key)
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
    // v2.0.140：opencode-apple 第二组订阅（同步拉取）
    @State private var opencodeAppleModels: [String] = []
    // v3.0.4：SenseNova（商汤）订阅模型（同步拉取）
    @State private var sensenovaModels: [String] = []
    // v3.0.4：通用 provider 列表（后端 model-providers 聚合——新增 provider 免改版）
    @State private var allProviders: [(id: String, models: [String])] = []
    // v3.0.4：用户手动隐藏的 provider（存 UserDefaults，可恢复）
    @State private var hiddenProviders: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "qingliao_hidden_providers") ?? [])
    // v3.0.4：用户手动隐藏的单个模型（"provider:model" 形式）
    @State private var hiddenModels: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "qingliao_hidden_models") ?? [])
    // v2.0.83：当前 provider（区分 opencode 的 deepseek 与官方 deepseek——同名模型不能同时勾）
    @AppStorage("qingliao_provider") private var currentProvider = "opencode"
    // v3.0.33：Agent 模型覆盖提示（Agent 开关开且配置了 agent 模型时，聊天实际走 agent 模型）
    @AppStorage("qingliao_agent_model") private var agentModel = ""
    @AppStorage("qingliao_agent_enabled") private var agentOn = true
    // v3.0.18：本地模型（Ollama 已安装，自主选择——动态拉取 /api/local/models）
    @State private var localInstalled: [String] = []
    // v3.0.10：视觉模型配置弹窗（模型管理内导航）
    @State private var showVisionModelSheet = false

    /// v2.0.131：opencode 同步模型显示名映射（无映射的用 id 本身）
    private let opencodeNames: [String: String] = [
        "deepseek-v4-flash": "DeepSeek V4 Flash",
        "deepseek-v4-pro": "DeepSeek V4 Pro",
        "kimi-k3": "Kimi K3",
        "kimi-k2.7-code": "Kimi K2.7 Code",
        "kimi-k2.6": "Kimi K2.6",
        "kimi-k2.5": "Kimi K2.5",
        "glm-5.3": "GLM 5.3",
        "glm-5.2": "GLM 5.2",
        "glm-5.1": "GLM 5.1",
        "glm-5": "GLM 5",
        "qwen3.8-max": "Qwen3.8 Max",
        "qwen3.7-max": "Qwen3.7 Max",
        "qwen3.7-plus": "Qwen3.7 Plus",
        "qwen3.6-plus": "Qwen3.6 Plus",
        "qwen3.5-plus": "Qwen3.5 Plus",
        "minimax-m3": "MiniMax M3",
        "minimax-m2.7": "MiniMax M2.7",
        "minimax-m2.5": "MiniMax M2.5",
        "mimo-v2.5-pro": "MiMo V2.5 Pro",
        "mimo-v2.5": "MiMo V2.5",
        "mimo-v2-pro": "MiMo V2 Pro",
        "mimo-v2-omni": "MiMo V2 Omni",
        "gpt-5.6-luna": "GPT-5.6 Luna",
        "grok-4.5": "Grok 4.5",
    ]

    /// v3.0.4：SenseNova（商汤）模型显示名映射
    private let sensenovaNames: [String: String] = [
        "sensenova-6.8-flash-lite": "SenseNova 6.8 Flash Lite",
        "sensenova-6.7-flash-lite": "SenseNova 6.7 Flash Lite",
        "sensenova-u1-fast": "SenseNova U1 Fast",
        "deepseek-v4-flash": "DeepSeek V4 Flash",
        "glm-5.2": "GLM 5.2",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                // 在线状态 + 同步结果
                HStack(spacing: 5) {
                Circle().fill(syncing ? Color.orange : Color.green).frame(width: 7, height: 7)
                Text(syncing ? "同步中..." : "模型服务在线")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let syncResult {
                Text(syncResult)
                    .font(.system(size: 11))
                    .foregroundStyle(syncResult.hasPrefix("✅") ? Color.green : Color.orange)
            }
            // v3.0.33：Agent 模型覆盖提示——Agent 开关开且配置了 agent 模型时，
            // 聊天实际走 agent 模型（视觉模型 > Agent 模型 > 主模型），此处选主模型不会生效
            if agentOn && !agentModel.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("聊天实际使用 Agent 模型：\(agentModel)")
                            .font(.system(size: 13, weight: .medium))
                        Text("Agent 开关开启时优先用 Agent 模型，这里设置主模型不生效；可在设置页「Agent 模型」改为跟随主模型")
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(11)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.8)
                )
            }
            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    if !opencodeAppleModels.isEmpty {
                        // v2.0.140：第二组 opencode 订阅（apple），同名模型按 provider 区分勾选
                        groupSection("opencode（apple）", models: opencodeAppleModels.map { ($0, opencodeNames[$0] ?? $0, "opencode-apple") })
                    }
                    if !deepseekModels.isEmpty {
                        // v2.0.83：官方 API 分组标注（与 opencode 的 deepseek 区分）
                        groupSection("deepseek（官方）", models: deepseekModels.map { ($0, $0, "deepseek") })
                    }
                    if !stepfunModels.isEmpty {
                        groupSection("stepfun", models: stepfunModels.map { ($0, $0, "stepfun") })
                    }
                    // v3.0.4：SenseNova（商汤）订阅模型分组
                    if !sensenovaModels.isEmpty {
                        groupSection("sensenova（商汤）", models: sensenovaModels.map { ($0, sensenovaNames[$0] ?? $0, "sensenova") })
                    }
                    // v2.0.118：本地模型（动态显示 Ollama 已安装模型——自主选择）
                    if !localInstalled.isEmpty {
                        groupSection("本地模型（断网兜底）", models: localInstalled.map { ($0, $0 + " · 本地", "local") })
                    }
                    // v3.0.4：通用 provider 分组（后端聚合——新增 provider 免改版，自动出现）
                    // 跳过已在上面硬编码渲染的 provider（避免重复），只渲染新增/未知的（如 xiaomi）
                    ForEach(allProviders, id: \.id) { p in
                        let hardcoded = ["opencode", "opencode-apple", "deepseek", "stepfun", "sensenova", "local"]
                        if !hardcoded.contains(p.id) && !hiddenProviders.contains(p.id) && !p.models.isEmpty {
                            groupSection(providerDisplayName(p.id),
                                         models: p.models.filter { !hiddenModels.contains("\(p.id):\($0)") }.map {
                                         ($0, providerModelDisplayName(p.id, $0), p.id) },
                                         onHideProvider: { toggleHideProvider(p.id) })
                        }
                    }
                    // 管理隐藏的 provider（恢复入口）
                    if !hiddenProviders.isEmpty {
                        Button {
                            hiddenProviders.removeAll()
                            UserDefaults.standard.set(Array(hiddenProviders), forKey: "qingliao_hidden_providers")
                        } label: {
                            Text("恢复全部隐藏的模型组")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    // v3.0.10：视觉模型配置（模型管理内导航）
                    Divider()
                        .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("视觉模型")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        HStack(spacing: 10) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visionModelDisplay)
                                    .font(.system(size: 13, weight: .medium))
                                Text("主模型不支持视觉时自动切换")
                                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(11)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 0.8)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { showVisionModelSheet = true }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(18)
        .navigationTitle("模型管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { syncList() } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .onAppear {
            selected = current
            // v2.0.118：动态拉取本地已装模型（自主选择）
            Task {
                if let j = try? await auth.json("/api/local/models") {
                    localInstalled = (j["models"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "" }
                }
            }
            // 恢复上次同步的模型（UserDefaults 持久化，无需每次点同步）
            if let s = UserDefaults.standard.array(forKey: "qingliao_models_stepfun") as? [String] {
                stepfunModels = s
            }
            if let d = UserDefaults.standard.array(forKey: "qingliao_models_deepseek") as? [String] {
                deepseekModels = d
            }
            // v2.0.140：恢复第二组 opencode（apple）同步结果
            if let a = UserDefaults.standard.array(forKey: "qingliao_models_opencode_apple") as? [String] {
                opencodeAppleModels = a
            }
            // v3.0.4：恢复 SenseNova（商汤）同步结果
            if let sn = UserDefaults.standard.array(forKey: "qingliao_models_sensenova") as? [String] {
                sensenovaModels = sn
            }
            // v3.0.4：恢复已隐藏 provider/模型
            hiddenProviders = Set(UserDefaults.standard.stringArray(forKey: "qingliao_hidden_providers") ?? [])
            hiddenModels = Set(UserDefaults.standard.stringArray(forKey: "qingliao_hidden_models") ?? [])
            // v3.0.4：首次打开自动拉取通用 provider 列表（免手动同步）
            if allProviders.isEmpty {
                // v3.0.35：先展示缓存（有则免转圈/免空白），后台刷新替换
                if !ModelProvidersCache.load().isEmpty {
                    allProviders = ModelProvidersCache.load()
                }
                Task { await loadAllProviders() }
            }
        }
        // v3.0.10：视觉模型配置弹窗（模型管理内导航）
        .sheet(isPresented: $showVisionModelSheet) {
            VisionModelSheet()
        }
        }
    }

    /// 分组标题 + 模型行（v3.0.4：可选 onHideProvider 显示分组隐藏按钮）
    private func groupSection(_ group: String, models: [(String, String, String)],
                              onHideProvider: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onHideProvider {
                    Button {
                        onHideProvider()
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 4)
            ForEach(models, id: \.0) { m in
                modelRow(id: m.0, name: m.1, provider: m.2)
            }
        }
    }

    /// v3.0.4：provider 显示名（已知映射用中文名，未知用 id）
    private func providerDisplayName(_ id: String) -> String {
        switch id {
        case "opencode": return "opencode（google）"
        case "opencode-apple": return "opencode（apple）"
        case "stepfun": return "stepfun"
        case "deepseek": return "deepseek（官方）"
        case "sensenova": return "sensenova（商汤）"
        case "xiaomi": return "xiaomi（小米）"
        case "local": return "本地模型（断网兜底）"
        default: return id
        }
    }

    /// v3.0.4：provider 内模型显示名（复用现有映射，未知用 id）
    private func providerModelDisplayName(_ pid: String, _ model: String) -> String {
        switch pid {
        case "opencode", "opencode-apple": return opencodeNames[model] ?? model
        case "sensenova": return sensenovaNames[model] ?? model
        default: return model
        }
    }

    /// v3.0.4：隐藏一个 provider 分组（存 UserDefaults，可"恢复全部"）
    private func toggleHideProvider(_ id: String) {
        hiddenProviders.insert(id)
        UserDefaults.standard.set(Array(hiddenProviders), forKey: "qingliao_hidden_providers")
    }

    private func modelRow(id: String, name: String, provider: String) -> some View {
        // v2.0.83：当前判定 = 模型 id + provider 双重匹配（opencode 与官方的 deepseek 同名不同源，不能同时勾）
        let isCur = selected == id && currentProvider == provider
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(id)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCur ? Color.accentColor : Color.primary)
                Text(name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCur {
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
            // v3.0.34：4 个 provider 并发同步（async let），最坏 40s → ~10s（失效 key 快速失败）
            async let stepfun = fetchModels("stepfun")
            async let deepseek = fetchModels("deepseek")
            // v2.0.140：同步 opencode（apple）订阅
            async let opencodeApple = fetchModels("opencode-apple")
            // v3.0.4：同步 SenseNova（商汤）订阅模型
            async let sensenova = fetchModels("sensenova")
            let (s, d, oa, sn) = await (stepfun, deepseek, opencodeApple, sensenova)
            if let s {
                stepfunModels = s
                UserDefaults.standard.set(s, forKey: "qingliao_models_stepfun")
            }
            if let d {
                deepseekModels = d
                UserDefaults.standard.set(d, forKey: "qingliao_models_deepseek")
            }
            if let oa {
                opencodeAppleModels = oa
                UserDefaults.standard.set(oa, forKey: "qingliao_models_opencode_apple")
            }
            if let sn {
                sensenovaModels = sn
                UserDefaults.standard.set(sn, forKey: "qingliao_models_sensenova")
            }
            // v3.0.4：通用拉取全部 provider（含新增，免改版）
            await loadAllProviders()
            // v3.0.4 fix：syncResult 放在所有赋值之后，计数才准确（原在 sn 赋值前显示=旧值0）
            syncResult = "✅ 已同步（apple \(opencodeAppleModels.count) / stepfun \(stepfunModels.count) / deepseek \(deepseekModels.count) / sensenova \(sensenovaModels.count)）"
            syncing = false
        }
    }

    private func fetchModels(_ provider: String) async -> [String]? {
        guard let j = try? await auth.json("/api/stream/sync-models?provider=\(provider)"),
              (j["ok"] as? Bool) == true,
              let list = j["models"] as? [String] else { return nil }
        return list
    }

    /// v3.0.4：通用拉取所有 provider + 模型（后端聚合接口——新 provider 免改版，自动出现）
    private func loadAllProviders() async {
        guard let j = try? await auth.json("/api/stream/model-providers?with_models=1"),
              (j["ok"] as? Bool) == true,
              let plist = j["providers"] as? [[String: Any]] else { return }
        var result: [(id: String, models: [String])] = []
        for p in plist {
            guard let id = p["id"] as? String else { continue }
            // v3.0.34：不再对空 models 逐个补拉 sync-models（N+1）——聚合接口已并发+缓存，
            // 失效 key 的 provider 补拉也是空/401，纯拖慢同步；直接采用聚合结果
            let models = (p["models"] as? [String]) ?? []
            result.append((id: id, models: models))
        }
        allProviders = result
        // v3.0.35：写缓存（微信通道/Agent/视觉模型共用），下次打开任何入口先显示缓存
        ModelProvidersCache.save(result)
    }

    /// v3.0.10：视觉模型显示文案（模型管理内导航行）
    private var visionModelDisplay: String {
        let mainModel = UserDefaults.standard.string(forKey: "qingliao_model") ?? "deepseek-v4-flash"
        guard CloudConfig.visionFallbackEnabled else { return "视觉模型 · 已关闭" }
        if CloudConfig.modelSupportsVision(mainModel) { return "视觉模型 · 主模型支持" }
        guard let vm = CloudConfig.localVisionModel, !vm.isEmpty else { return "视觉模型 · 未配置" }
        return "视觉模型 · \(vm)"
    }
}

// MARK: - 关于轻聊（软件介绍页）

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth   // v3.0.8：拉 Hermes 版本
    // v3.0.1：云端模式文案区分（本地 AI = 连接自家 NAS；云端 AI = 直连大模型 API）
    var isCloud: Bool = false
    // v3.0.8：Hermes 容器版本（项目版本说明，从 NAS /api/nas/status 实时读）
    @State private var hermesVersion = "读取中…"

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
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 10) {
                // v3.0.8：项目版本说明（iOS 客户端版本）
                aboutRow("项目版本", "轻聊 3.0 · iOS 客户端 v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                // v3.0.3：统一介绍框架——顶部 App 概述（两端一致），下方「当前模式」针对云端/本地分别说明
                aboutRow("产品", "轻聊 —— 面向家庭的 AI 智能助手，SwiftUI 原生客户端，支持「本地 AI」与「云端 AI」两种形态，数据按模式本地保存。")
                appModeRow(isCloud)
                aboutRow("功能", isCloud
                          ? "流式对话 · 语音输入 · 会话本地保存 · 天气查询"
                          : "流式对话 · 语音对话 · 图片理解 · 知识库检索 · 会话同步 · NAS 面板 · Docker 管理 · 智能家居 · 定时任务")
                aboutRow("模型", isCloud
                          ? "DeepSeek / Kimi / GLM / MiniMax / OpenAI 等 OpenAI 兼容服务多厂商接入"
                          : "DeepSeek V4 / Kimi / StepFun 多模型聚合（OpenCode Go + 官方 API）")
                aboutRow("架构", isCloud
                          ? "SwiftUI 原生 · 轻聊 3.0 云端模式 · 直连云端 API（Wi-Fi / 蜂窝均可）"
                          : "SwiftUI 原生 · Hermes Agent · 自建 NAS 后端（连接自家 NAS）")
                // v3.0.8：Hermes Agent 版本号固定放在介绍最后一行（本地模式读容器实时版本）
                if !isCloud {
                    HStack(alignment: .top) {
                        Text("Hermes Agent")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 68, alignment: .leading)
                        Text(hermesVersion)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
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
        // v3.0.8：本地模式拉取 Hermes 版本
        .task {
            guard !isCloud else { return }
            if let j = try? await auth.json("/api/nas/status"),
               let svc = j["services"] as? [String: Any],
               let v = svc["hermes_version"] as? String, !v.isEmpty {
                hermesVersion = v
            } else {
                hermesVersion = "未获取到"
            }
        }
    }

    /// v3.0.3：当前模式行（云端/本地分别说明，含差异化介绍）
    @ViewBuilder
    private func appModeRow(_ cloud: Bool) -> some View {
        if cloud {
            aboutRow("当前模式", "云端 AI —— 无需本地服务器，直连主流大模型 API，配置即用，数据全部保存在手机本地。")
        } else {
            aboutRow("当前模式", "本地 AI —— 连接自家 NAS 上的 Hermes Agent，对话/读图/语音/知识库/智能家居全掌控。")
        }
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

// MARK: - v3.0.19 微信通道模型设置（方案B：读写 Hermes wechat-profile，微信通道专属模型）

struct WechatChannelSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var currentModel = "读取中…"
    @State private var currentProvider = ""
    @State private var allProviders: [(id: String, models: [String])] = []
    @State private var saving = false
    @State private var saveResult: String?
    @State private var loaded = false
    // v3.0.35：模型列表加载失败（区别于"加载中"——失败时不再无限转圈）
    @State private var loadFailed = false
    // v3.0.35：当前展示的是缓存数据（顶部提示，避免误以为未刷新）
    @State private var usingCache = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                // 当前模型 + 说明
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(loaded ? Color.green : Color.orange).frame(width: 7, height: 7)
                        Text("当前微信通道模型")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(currentModel)
                        .font(.system(size: 15, weight: .semibold))
                    Text("设置后重启 Hermes 生效（约 10-30 秒），只影响微信通道，其他通道不受影响。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let saveResult {
                Text(saveResult)
                    .font(.system(size: 11))
                    .foregroundStyle(saveResult.hasPrefix("✅") ? Color.green : Color.orange)
            }

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    if allProviders.isEmpty {
                        if loadFailed {
                            // v3.0.35：加载失败态 + 重试（不再无限转圈）
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.orange)
                                Text("模型列表加载失败")
                                    .font(.system(size: 13, weight: .medium))
                                Text("请检查网络或后端服务后重试")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Button {
                                    loadFailed = false
                                    Task { await loadProviders() }
                                } label: {
                                    Text("重试")
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 18).padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 30)
                        } else {
                            ProgressView()
                                .padding(.top, 30)
                            Text("正在加载模型列表…")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    } else {
                        // v3.0.35：缓存数据展示提示（后台刷新成功后自动消失）
                        if usingCache {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 9))
                                Text("显示上次加载的列表，正在刷新…")
                                    .font(.system(size: 10.5))
                            }
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                        // v3.0.19 review：全部 provider 模型为空 → 空态提示（防白屏）
                        let hasAnyModel = allProviders.contains { !$0.models.isEmpty }
                        if !hasAnyModel {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.tertiary)
                                Text("暂无可用模型\n（后端未配置 provider key，请到「模型管理」检查）")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 40)
                        }
                        ForEach(allProviders, id: \.id) { p in
                            if !p.models.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(providerName(p.id))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                    ForEach(p.models, id: \.self) { m in
                                        Button {
                                            saveModel(provider: p.id, model: m)
                                        } label: {
                                            HStack {
                                                Text(m)
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                // 当前选中标记（model+provider 都匹配）
                                                if m == currentModel && p.id == currentProvider {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(Color.accentColor)
                                                } else {
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .navigationTitle("微信通道模型")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
            // v3.0.35：手动刷新（缓存过期/刷新失败后重拉）
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .task { await load() }
        }
    }

    /// 拉当前微信通道模型 + 全部 provider 模型列表
    /// v3.0.35：①缓存优先（打开即有列表，不转圈）②两个请求 async let 并发（原串行，channel/model 挂起会拖死 providers）
    private func load() async {
        // 1) 立即展示缓存
        if allProviders.isEmpty, !ModelProvidersCache.load().isEmpty {
            allProviders = ModelProvidersCache.load()
            usingCache = true
        }
        // 2) 并发刷新（互不阻塞）
        async let cm: Void = loadChannelModel()
        async let pl: Void = loadProviders()
        _ = await (cm, pl)
    }

    /// 拉当前微信通道模型（独立失败不影响模型列表）
    private func loadChannelModel() async {
        if let j = try? await auth.json("/api/channel/model") {
            currentModel = (j["model"] as? String) ?? "未设置"
            currentProvider = (j["provider"] as? String) ?? ""
            loaded = true
        } else {
            currentModel = "读取失败（后端需 v3.0.19）"
        }
    }

    /// 拉 provider 模型列表（成功写缓存；失败置 loadFailed，有缓存则保留缓存展示）
    private func loadProviders() async {
        do {
            let j = try await auth.json("/api/stream/model-providers?with_models=1")
            guard (j["ok"] as? Bool) == true, let plist = j["providers"] as? [[String: Any]] else {
                throw APIError.badJSON
            }
            var result: [(id: String, models: [String])] = []
            for p in plist {
                guard let id = p["id"] as? String else { continue }
                let models = (p["models"] as? [String]) ?? []
                result.append((id: id, models: models))
            }
            allProviders = result
            ModelProvidersCache.save(result)
            usingCache = false
            loadFailed = false
        } catch {
            // 有缓存则保留缓存展示；无缓存时 UI 显示失败态+重试
            if allProviders.isEmpty {
                loadFailed = true
            }
        }
    }

    /// 保存微信通道模型（POST /api/channel/model → 后端改 wechat-profile + 重启 gateway）
    private func saveModel(provider: String, model: String) {
        guard !saving else { return }
        saving = true
        saveResult = nil
        Task {
            defer { saving = false }
            do {
                let j = try await auth.json("/api/channel/model", method: "POST",
                                            body: ["model": model, "provider": provider])
                if (j["ok"] as? Bool) == true {
                    currentModel = model
                    currentProvider = provider
                    UserDefaults.standard.set(model, forKey: "qingliao_wechat_channel_model")
                    saveResult = "✅ 已设置：\(model)（gateway 重启后生效，约 10-30 秒）"
                } else {
                    saveResult = "⚠️ 设置失败：\(j["error"] as? String ?? "未知错误")"
                }
            } catch {
                saveResult = "⚠️ 设置失败：\(error.localizedDescription)"
            }
        }
    }

    /// provider 显示名
    private func providerName(_ id: String) -> String {
        switch id {
        case "opencode": return "opencode（google）"
        case "opencode-apple": return "opencode（apple）"
        case "deepseek": return "deepseek（官方）"
        case "stepfun": return "stepfun"
        case "sensenova": return "sensenova（商汤）"
        case "xiaomi": return "xiaomi"
        case "ollama": return "本地模型（Ollama）"
        default: return id
        }
    }
}

// MARK: - v3.0.20 Agent 模型选择（独立于主模型，可单独指定 Agent 使用的模型）

struct AgentModelSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @AppStorage("qingliao_agent_model") private var agentModel = ""
    @AppStorage("qingliao_agent_provider") private var agentProvider = ""
    @AppStorage("qingliao_model") private var mainModel = "deepseek-v4-flash"
    @AppStorage("qingliao_provider") private var mainProvider = "opencode"

    @State private var selected = ""
    @State private var selectedProvider = ""
    @State private var syncing = false
    @State private var syncResult: String?
    @State private var allProviders: [(id: String, models: [String])] = []
    @State private var localInstalled: [String] = []
    // v3.0.35：模型列表加载失败（不再无限转圈）
    @State private var loadFailed = false

    /// opencode 模型显示名映射
    private let opencodeNames: [String: String] = [
        "deepseek-v4-flash": "DeepSeek V4 Flash",
        "deepseek-v4-flash-free": "DeepSeek V4 Flash Free",
        "deepseek-v4-pro": "DeepSeek V4 Pro",
        "kimi-k3": "Kimi K3",
        "kimi-k2.7-code": "Kimi K2.7 Code",
        "kimi-k2.6": "Kimi K2.6",
        "kimi-k2.5": "Kimi K2.5",
        "glm-5.3": "GLM 5.3",
        "glm-5.2": "GLM 5.2",
        "glm-5.1": "GLM 5.1",
        "glm-5": "GLM 5",
        "qwen3.8-max": "Qwen3.8 Max",
        "qwen3.7-max": "Qwen3.7 Max",
        "qwen3.7-plus": "Qwen3.7 Plus",
        "qwen3.6-plus": "Qwen3.6 Plus",
        "qwen3.5-plus": "Qwen3.5 Plus",
        "minimax-m3": "MiniMax M3",
        "minimax-m2.7": "MiniMax M2.7",
        "minimax-m2.5": "MiniMax M2.5",
        "mimo-v2.5-pro": "MiMo V2.5 Pro",
        "mimo-v2.5": "MiMo V2.5",
        "mimo-v2-pro": "MiMo V2 Pro",
        "mimo-v2-omni": "MiMo V2 Omni",
        "gpt-5.6-luna": "GPT-5.6 Luna",
        "grok-4.5": "Grok 4.5",
    ]

    private let sensenovaNames: [String: String] = [
        "sensenova-6.8-flash-lite": "SenseNova 6.8 Flash Lite",
        "sensenova-6.7-flash-lite": "SenseNova 6.7 Flash Lite",
        "sensenova-u1-fast": "SenseNova U1 Fast",
        "deepseek-v4-flash": "DeepSeek V4 Flash",
        "glm-5.2": "GLM 5.2",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                // 当前状态
                HStack(spacing: 5) {
                    Circle().fill(syncing ? Color.orange : Color.green).frame(width: 7, height: 7)
                    Text(syncing ? "同步中..." : "Agent 模型设置")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let syncResult {
                    Text(syncResult)
                        .font(.system(size: 11))
                        .foregroundStyle(syncResult.hasPrefix("✅") ? Color.green : Color.orange)
                }

                // 跟随主模型选项
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("跟随主模型")
                                .font(.system(size: 13, weight: .medium))
                            Text("当前主模型：\(mainModel)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if selected.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(11)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(selected.isEmpty ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                                          lineWidth: 0.8)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = ""
                        selectedProvider = ""
                    }
                }

                Divider()

                ScrollView {
                    VStack(spacing: 12) {
                        if allProviders.isEmpty && localInstalled.isEmpty {
                            if loadFailed {
                                // v3.0.35：加载失败态 + 重试（不再无限转圈）
                                VStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.orange)
                                    Text("模型列表加载失败")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("请检查网络或后端服务后重试")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    Button {
                                        loadFailed = false
                                        Task { await loadAllProviders() }
                                    } label: {
                                        Text("重试")
                                            .font(.system(size: 12, weight: .medium))
                                            .padding(.horizontal, 18).padding(.vertical, 6)
                                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 30)
                            } else {
                                ProgressView()
                                    .padding(.top, 30)
                                Text("正在加载模型列表…")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        } else {
                            // 按 provider 分组显示（v3.0.29 fix：移除 hardcoded 过滤，所有 provider 均展示）
                            ForEach(allProviders, id: \.id) { p in
                                if !p.models.isEmpty {
                                    agentGroupSection(providerDisplayName(p.id),
                                                      models: p.models.map { ($0, providerModelDisplayName(p.id, $0), p.id) })
                                }
                            }
                            // 本地模型
                            if !localInstalled.isEmpty {
                                agentGroupSection("本地模型（断网兜底）",
                                                  models: localInstalled.map { ($0, $0 + " · 本地", "local") })
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(18)
            .navigationTitle("Agent 模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        agentModel = selected
                        agentProvider = selectedProvider
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await syncList() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .onAppear {
                selected = agentModel
                selectedProvider = agentProvider
                // v3.0.35：先展示缓存（打开即有列表不转圈），后台刷新成功后替换
                if allProviders.isEmpty, !ModelProvidersCache.load().isEmpty {
                    allProviders = ModelProvidersCache.load()
                }
                Task { await loadAllProviders() }
            }
        }
    }

    /// 分组标题 + 模型行
    private func agentGroupSection(_ group: String, models: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(models, id: \.0) { m in
                agentModelRow(id: m.0, name: m.1, provider: m.2)
            }
        }
    }

    private func agentModelRow(id: String, name: String, provider: String) -> some View {
        let isCur = selected == id && selectedProvider == provider
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(id)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCur ? Color.accentColor : Color.primary)
                Text(name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCur {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                    Text("当前").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            } else {
                Button {
                    selected = id
                    selectedProvider = provider
                } label: {
                    Text("选用")
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
                .strokeBorder(isCur ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                              lineWidth: 0.8)
        )
    }

    private func providerDisplayName(_ id: String) -> String {
        switch id {
        case "opencode": return "opencode（google）"
        case "opencode-apple": return "opencode（apple）"
        case "stepfun": return "stepfun"
        case "deepseek": return "deepseek（官方）"
        case "sensenova": return "sensenova（商汤）"
        case "xiaomi": return "xiaomi（小米）"
        case "local": return "本地模型（断网兜底）"
        default: return id
        }
    }

    private func providerModelDisplayName(_ pid: String, _ model: String) -> String {
        switch pid {
        case "opencode", "opencode-apple": return opencodeNames[model] ?? model
        case "sensenova": return sensenovaNames[model] ?? model
        default: return model
        }
    }

    /// 拉取所有 provider 的模型列表（v3.0.35：成功写缓存，失败置 loadFailed，有缓存则保留缓存展示）
    private func loadAllProviders() async {
        do {
            let j = try await auth.json("/api/stream/model-providers?with_models=1")
            let plist = (j["providers"] as? [[String: Any]]) ?? []
            var result: [(id: String, models: [String])] = []
            for p in plist {
                guard let id = p["id"] as? String,
                      let models = p["models"] as? [String] else { continue }
                result.append((id: id, models: models))
            }
            allProviders = result
            ModelProvidersCache.save(result)
            loadFailed = false
        } catch {
            // 有缓存则保留缓存展示；无缓存时 UI 显示失败态+重试
            if allProviders.isEmpty && localInstalled.isEmpty {
                loadFailed = true
            }
        }
    }

    /// 同步模型列表
    private func syncList() async {
        guard !syncing else { return }
        syncing = true
        syncResult = nil
        await loadAllProviders()
        // 本地模型
        if let j = try? await auth.json("/api/local/models") {
            localInstalled = (j["models"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "" }
        }
        syncing = false
        syncResult = "✅ 已刷新"
    }
}
