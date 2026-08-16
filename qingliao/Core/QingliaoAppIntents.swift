import AppIntents
import Foundation

// MARK: - v2.0.116 Siri 快捷指令（AppIntents，App 内实现，无 extension，侧载可用）

/// 打开轻聊
@MainActor
struct OpenQingliaoIntent: AppIntent {
    static var title: LocalizedStringResource = "打开轻聊"
    static var description = IntentDescription("打开轻聊 AI 对话")

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

/// 执行场景（Siri：「用轻聊执行场景 离家模式」）
@MainActor
struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "执行场景"
    static var description = IntentDescription("执行一个智能家居场景")

    @Parameter(title: "场景名")
    var sceneName: String

    func perform() async throws -> some IntentResult {
        // Siri 唤起时 App 进程已启动——直接用存储的服务器/凭据调用后端
        let defaults = UserDefaults.standard
        let server = defaults.string(forKey: "qingliao_server") ?? ""
        let token = defaults.string(forKey: "qingliao_token") ?? ""
        if !server.isEmpty, !token.isEmpty {
            var base = server
            if !base.hasPrefix("http") { base = "http://" + base }
            if let url = URL(string: base + "/api/scenes/run") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 15
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(token, forHTTPHeaderField: "X-Auth-Token")
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": sceneName])
                _ = try? await URLSession.shared.data(for: req)
            }
        }
        return .result()
    }
}

/// 向轻聊提问（Siri：「问轻聊 现在几点了」）——打开 App 并带问题
@MainActor
struct AskQingliaoIntent: AppIntent {
    static var title: LocalizedStringResource = "向轻聊提问"
    static var description = IntentDescription("向轻聊 AI 提问并打开对话")

    @Parameter(title: "问题")
    var question: String

    func perform() async throws -> some IntentResult {
        // 存到 UserDefaults，App 前台读取后自动发送
        UserDefaults.standard.set(question, forKey: "qingliao_siri_question")
        return .result()
    }
}
