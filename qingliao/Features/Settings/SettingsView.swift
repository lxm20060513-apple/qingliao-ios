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
}
