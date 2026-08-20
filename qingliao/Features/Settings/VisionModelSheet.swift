import SwiftUI

// MARK: - v3.0.10 视觉模型配置（本地 AI 设置：模型管理下新增）

/// 从模型管理列表中选择视觉模型——主模型不支持视觉时自动切换
struct VisionModelSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = CloudConfig.visionFallbackEnabled
    @State private var selectedModel: String = CloudConfig.localVisionModel ?? ""
    @State private var selectedProvider: String = CloudConfig.localVisionProvider

    // 同步的模型列表（复用 ModelSheet 的数据源）
    @State private var allProviders: [(id: String, models: [String])] = []
    @State private var opencodeModels: [String] = []
    @State private var opencodeAppleModels: [String] = []
    @State private var deepseekModels: [String] = []
    @State private var stepfunModels: [String] = []
    @State private var sensenovaModels: [String] = []
    @State private var localInstalled: [String] = []

    // 当前主模型（判断是否支持视觉）
    @AppStorage("qingliao_model") private var mainModel = "deepseek-v4-flash"
    private var mainModelSupportsVision: Bool {
        CloudConfig.modelSupportsVision(mainModel)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 开关 + 状态
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.purple, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("视觉模型自动切换").font(.system(size: 14, weight: .medium))
                            Text(statusText)
                                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: $enabled).labelsHidden().scaleEffect(0.8).tint(.green)
                            .onChange(of: enabled) { _, new in
                                CloudConfig.setVisionFallbackEnabled(new)
                            }
                    }
                }

                if enabled {
                    // MARK: - 主模型状态
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: mainModelSupportsVision ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(mainModelSupportsVision ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("主模型：\(mainModel)")
                                    .font(.system(size: 13, weight: .medium))
                                Text(mainModelSupportsVision
                                     ? "已支持视觉，无需配置备用模型"
                                     : "不支持视觉，发送图片时将使用下方配置的视觉模型")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // MARK: - 已选视觉模型
                    if !selectedModel.isEmpty {
                        Section("当前视觉模型") {
                            HStack(spacing: 10) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedModel)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(providerDisplayName(selectedProvider))
                                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button("清除") {
                                    selectedModel = ""
                                    selectedProvider = "opencode"
                                    CloudConfig.clearVisionModel()
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    // MARK: - 模型列表选择
                    Section("选择视觉模型") {
                        if opencodeModels.isEmpty && deepseekModels.isEmpty && localInstalled.isEmpty && allProviders.isEmpty {
                            Text("暂无可用模型\n请先在「模型管理」中同步模型列表")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            // opencode 模型
                            if !opencodeModels.isEmpty {
                                modelGroup("opencode（google）", provider: "opencode", models: opencodeModels)
                            }
                            if !opencodeAppleModels.isEmpty {
                                modelGroup("opencode（apple）", provider: "opencode-apple", models: opencodeAppleModels)
                            }
                            if !deepseekModels.isEmpty {
                                modelGroup("deepseek（官方）", provider: "deepseek", models: deepseekModels)
                            }
                            if !stepfunModels.isEmpty {
                                modelGroup("stepfun", provider: "stepfun", models: stepfunModels)
                            }
                            if !sensenovaModels.isEmpty {
                                modelGroup("sensenova（商汤）", provider: "sensenova", models: sensenovaModels)
                            }
                            if !localInstalled.isEmpty {
                                modelGroup("本地模型", provider: "local", models: localInstalled)
                            }
                            // 通用 provider
                            let hardcoded = ["opencode", "opencode-apple", "deepseek", "stepfun", "sensenova", "local"]
                            ForEach(allProviders.filter { !hardcoded.contains($0.id) && !$0.models.isEmpty }, id: \.id) { p in
                                modelGroup(providerDisplayName(p.id), provider: p.id, models: p.models)
                            }
                        }
                    }
                }
            }
            .navigationTitle("视觉模型配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await syncModels() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await loadCachedModels() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 子视图

    private func modelGroup(_ group: String, provider: String, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.vertical, 4)
            ForEach(models, id: \.self) { model in
                let isSelected = selectedModel == model && selectedProvider == provider
                let name = modelDisplayName(provider: provider, model: model)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        if model != name {
                            Text(model)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Button("选择") {
                            selectedModel = model
                            selectedProvider = provider
                            CloudConfig.setVisionModel(model, provider: provider)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - 数据加载

    private var statusText: String {
        if !enabled { return "已关闭" }
        if mainModelSupportsVision { return "主模型支持视觉，无需配置" }
        if selectedModel.isEmpty { return "未配置视觉模型" }
        return "已配置：\(selectedModel)"
    }

    private func modelDisplayName(provider: String, model: String) -> String {
        switch provider {
        case "opencode", "opencode-apple":
            let names: [String: String] = [
                "deepseek-v4-flash": "DeepSeek V4 Flash",
                "deepseek-v4-flash-free": "DeepSeek V4 Flash Free",
                "deepseek-v4-pro": "DeepSeek V4 Pro",
                "kimi-k3": "Kimi K3", "kimi-k2.7-code": "Kimi K2.7 Code",
                "kimi-k2.6": "Kimi K2.6", "kimi-k2.5": "Kimi K2.5",
                "glm-5.3": "GLM 5.3", "glm-5.2": "GLM 5.2", "glm-5.1": "GLM 5.1", "glm-5": "GLM 5",
                "qwen3.8-max": "Qwen3.8 Max", "qwen3.7-max": "Qwen3.7 Max",
                "qwen3.7-plus": "Qwen3.7 Plus", "qwen3.6-plus": "Qwen3.6 Plus",
                "minimax-m3": "MiniMax M3", "minimax-m2.7": "MiniMax M2.7", "minimax-m2.5": "MiniMax M2.5",
                "mimo-v2.5-pro": "MiMo V2.5 Pro", "mimo-v2.5": "MiMo V2.5",
                "mimo-v2-pro": "MiMo V2 Pro", "mimo-v2-omni": "MiMo V2 Omni",
                "gpt-5.6-luna": "GPT-5.6 Luna", "grok-4.5": "Grok 4.5",
            ]
            return names[model] ?? model
        case "sensenova":
            let names: [String: String] = [
                "sensenova-6.8-flash-lite": "SenseNova 6.8 Flash Lite",
                "sensenova-6.7-flash-lite": "SenseNova 6.7 Flash Lite",
                "sensenova-u1-fast": "SenseNova U1 Fast",
            ]
            return names[model] ?? model
        default:
            return model
        }
    }

    private func providerDisplayName(_ id: String) -> String {
        switch id {
        case "opencode": return "opencode（google）"
        case "opencode-apple": return "opencode（apple）"
        case "deepseek": return "deepseek（官方）"
        case "stepfun": return "stepfun"
        case "sensenova": return "sensenova（商汤）"
        case "local": return "本地模型"
        default: return id
        }
    }

    private func loadCachedModels() async {
        // 从 UserDefaults 恢复缓存的模型列表
        if let s = UserDefaults.standard.array(forKey: "qingliao_models_stepfun") as? [String] { stepfunModels = s }
        if let d = UserDefaults.standard.array(forKey: "qingliao_models_deepseek") as? [String] { deepseekModels = d }
        if let o = UserDefaults.standard.array(forKey: "qingliao_models_opencode") as? [String] { opencodeModels = o }
        if let a = UserDefaults.standard.array(forKey: "qingliao_models_opencode_apple") as? [String] { opencodeAppleModels = a }
        if let sn = UserDefaults.standard.array(forKey: "qingliao_models_sensenova") as? [String] { sensenovaModels = sn }
        // 本地 Ollama 模型
        if let j = try? await auth.json("/api/local/models") {
            localInstalled = (j["models"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "" }
        }
        // 通用 provider
        if allProviders.isEmpty {
            if let j = try? await auth.json("/api/stream/model-providers?with_models=1"),
               (j["ok"] as? Bool) == true,
               let plist = j["providers"] as? [[String: Any]] {
                var result: [(id: String, models: [String])] = []
                for p in plist {
                    guard let id = p["id"] as? String else { continue }
                    let models = (p["models"] as? [String]) ?? []
                    if !models.isEmpty { result.append((id: id, models: models)) }
                }
                allProviders = result
            }
        }
    }

    private func syncModels() async {
        // 复用后端 sync-models 接口
        async func fetch(_ provider: String) -> [String]? {
            guard let j = try? await auth.json("/api/stream/sync-models?provider=\(provider)"),
                  (j["ok"] as? Bool) == true,
                  let list = j["models"] as? [String] else { return nil }
            return list
        }
        if let s = await fetch("stepfun") {
            stepfunModels = s
            UserDefaults.standard.set(s, forKey: "qingliao_models_stepfun")
        }
        if let d = await fetch("deepseek") {
            deepseekModels = d
            UserDefaults.standard.set(d, forKey: "qingliao_models_deepseek")
        }
        if let o = await fetch("opencode") {
            opencodeModels = o
            UserDefaults.standard.set(o, forKey: "qingliao_models_opencode")
        }
        if let oa = await fetch("opencode-apple") {
            opencodeAppleModels = oa
            UserDefaults.standard.set(oa, forKey: "qingliao_models_opencode_apple")
        }
        if let sn = await fetch("sensenova") {
            sensenovaModels = sn
            UserDefaults.standard.set(sn, forKey: "qingliao_models_sensenova")
        }
        // 通用 provider
        if let j = try? await auth.json("/api/stream/model-providers?with_models=1"),
           (j["ok"] as? Bool) == true,
           let plist = j["providers"] as? [[String: Any]] {
            var result: [(id: String, models: [String])] = []
            for p in plist {
                guard let id = p["id"] as? String else { continue }
                let models = (p["models"] as? [String]) ?? []
                if !models.isEmpty { result.append((id: id, models: models)) }
            }
            allProviders = result
        }
    }
}
