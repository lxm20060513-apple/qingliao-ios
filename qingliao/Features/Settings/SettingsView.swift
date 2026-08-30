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
    // v3.0.74：钉一钉存储路径
    @State private var showPinPath = false
    @State private var pinPathEdit = ""
    private var pinPathDisplay: String {
        let p = PinStore.shared.storagePath
        return p.isEmpty ? "默认路径" : (p.count > 20 ? "..." + p.suffix(17) : p)
    }
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
            // v3.0.74：钉一钉存储路径
            Divider().padding(.leading, 52)
            SettingRow(icon: "pin.fill", iconColor: .indigo, title: "钉一钉存储",
                       value: pinPathDisplay, chevron: true)
                .onTapGesture { showPinPath = true }
        }
        .glassListCard()
        .sheet(isPresented: $showPinPath) {
            PinPathSheet()
                .presentationDetents([.medium, .large])
        }
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
            Text("退出后回到登录页，可切换本地 AI / 云端 AI 模式。云端配置（API Key）仍保留在手机本地。")
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
