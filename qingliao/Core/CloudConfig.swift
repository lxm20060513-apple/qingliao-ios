import Foundation
import Security

// MARK: - v3.0 云端模式配置（无本地服务器用户）

/// 模式：本地 AI（走自家 NAS 后端）/ 云端 AI（直连大模型 API）
enum QingliaoMode: String {
    case local = "local"     // 2.0 现有模式：连 NAS 后端
    case cloud = "cloud"     // 3.0 新模式：直连 OpenAI 兼容端点
}

/// 云端模型厂商预设（OpenAI 兼容端点）
struct CloudProviderPreset: Identifiable {
    let id: String           // 内部 id（也作 UserDefaults key 后缀）
    let name: String         // 显示名
    let baseURL: String      // 默认 base_url
    let defaultModel: String // 默认模型
    let apiKeyHint: String   // key 格式提示
    var supportsVision: Bool = false   // v3.0.4：默认模型是否支持视觉

    static let presets: [CloudProviderPreset] = [
        CloudProviderPreset(id: "deepseek", name: "DeepSeek",
                            baseURL: "https://api.deepseek.com/v1",
                            defaultModel: "deepseek-chat",
                            apiKeyHint: "sk-..."),
        CloudProviderPreset(id: "kimi", name: "Kimi (Moonshot)",
                            baseURL: "https://api.moonshot.cn/v1",
                            defaultModel: "moonshot-v1-8k",
                            apiKeyHint: "sk-..."),
        CloudProviderPreset(id: "glm", name: "智谱 GLM",
                            baseURL: "https://open.bigmodel.cn/api/paas/v4",
                            defaultModel: "glm-4-flash",
                            apiKeyHint: "从智谱开放平台获取"),
        CloudProviderPreset(id: "minimax", name: "MiniMax",
                            baseURL: "https://api.minimax.chat/v1",
                            defaultModel: "MiniMax-Text-01",
                            apiKeyHint: "从 MiniMax 开放平台获取"),
        CloudProviderPreset(id: "openai", name: "OpenAI",
                            baseURL: "https://api.openai.com/v1",
                            defaultModel: "gpt-4o-mini",
                            apiKeyHint: "sk-...",
                            supportsVision: true),   // v3.0.4：gpt-4o 系列支持视觉
        // v3.0.4：商汤日日新 SenseNova（Token Plan 免费，OpenAI 兼容）
        // 模型列表（fetchModels 动态拉）：sensenova-6.7-flash-lite / deepseek-v4-flash /
        // glm-5.2 / sensenova-u1-fast / sensenova-6.8-flash-lite
        CloudProviderPreset(id: "sensenova", name: "SenseNova(商汤)",
                            baseURL: "https://token.sensenova.cn/v1",
                            defaultModel: "deepseek-v4-flash",
                            apiKeyHint: "sensenova.cn 控制台获取"),
        CloudProviderPreset(id: "custom", name: "自定义 (OpenAI 兼容)",
                            baseURL: "",
                            defaultModel: "",
                            apiKeyHint: "任意 OpenAI 兼容服务"),
    ]
}

/// 云端配置（单个厂商连接信息）
struct CloudProviderConfig: Codable, Identifiable {
    var providerID: String      // 对应 preset id 或 "custom"
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String
    var supportsVision: Bool = false   // v3.0.4：是否支持视觉（图片降级判断）

    var id: String { providerID }   // v3.0: ForEach 需要 Identifiable
}

/// 云端配置存储（UserDefaults + Keychain）
/// - 配置列表存 UserDefaults（不含 key）
/// - api_key 存 Keychain（勿落 UserDefaults，防明文泄露）
@MainActor
@Observable
final class CloudConfig {
    static let shared = CloudConfig()

    /// 当前模式（本地 AI / 云端 AI）
    var mode: QingliaoMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "qingliao_mode") }
    }

    /// 已保存的厂商配置（不含 key，key 在 Keychain）
    private(set) var providers: [CloudProviderConfig] = []

    /// 当前选中的厂商 id
    var activeProviderID: String {
        didSet { UserDefaults.standard.set(activeProviderID, forKey: "qingliao_cloud_provider") }
    }

    private let defaults = UserDefaults.standard
    private let providersKey = "qingliao_cloud_providers"
    private let keychainPrefix = "qingliao_cloud_key_"

    init() {
        mode = QingliaoMode(rawValue: UserDefaults.standard.string(forKey: "qingliao_mode") ?? "") ?? .local
        activeProviderID = UserDefaults.standard.string(forKey: "qingliao_cloud_provider") ?? ""
        loadProviders()
        // 无厂商时预置一个 DeepSeek 空配置，方便首次进入
        if providers.isEmpty {
            let p = CloudProviderPreset.presets[0]
            providers.append(CloudProviderConfig(providerID: p.id, name: p.name,
                                                 baseURL: p.baseURL, apiKey: "", model: p.defaultModel))
            saveProviders()
            activeProviderID = p.id
        }
    }

    var isCloudMode: Bool { mode == .cloud }

    /// 切换模式（云端→本地 或反之）
    func setMode(_ m: QingliaoMode) { mode = m }

    /// 当前生效的云端配置（含 Keychain key）
    var activeConfig: CloudProviderConfig? {
        guard let idx = providers.firstIndex(where: { $0.providerID == activeProviderID }) else { return nil }
        var c = providers[idx]
        c.apiKey = keychainRead(keychainPrefix + c.providerID)
        return c
    }

    // MARK: - 厂商配置 CRUD

    func saveProvider(_ c: CloudProviderConfig) {
        if let idx = providers.firstIndex(where: { $0.providerID == c.providerID }) {
            providers[idx] = c
        } else {
            providers.append(c)
        }
        if !c.apiKey.isEmpty {
            keychainWrite(keychainPrefix + c.providerID, c.apiKey)
        }
        saveProviders()
    }

    func removeProvider(id: String) {
        providers.removeAll { $0.providerID == id }
        keychainDelete(keychainPrefix + id)
        saveProviders()
        if activeProviderID == id {
            activeProviderID = providers.first?.providerID ?? ""
        }
    }

    /// 校验云端配置是否可用（登录/聊天前）
    var isConfigured: Bool {
        guard let c = activeConfig, !c.baseURL.isEmpty, !c.apiKey.isEmpty, !c.model.isEmpty else { return false }
        return true
    }

    // MARK: - 私有

    private func loadProviders() {
        if let data = defaults.data(forKey: providersKey),
           let list = try? JSONDecoder().decode([CloudProviderConfig].self, from: data) {
            providers = list
        }
    }

    private func saveProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: providersKey)
        }
    }

    private func keychainWrite(_ key: String, _ value: String) {
        guard !value.isEmpty else { return }
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.qingliao.app.cloud",
            kSecAttrAccount as String: key,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func keychainRead(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.qingliao.app.cloud",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func keychainDelete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.qingliao.app.cloud",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
