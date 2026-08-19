import Foundation
import Observation

// MARK: - 便签 Store（v3.0.8 看板便签）
// 本地 AI 模式：存 NAS 后端（/api/notes，地址可在设置自定义，默认当前服务器）；云端模式：存 App 本地 UserDefaults。
// 双模式共用 UI（看板便签卡片），数据层按模式分流。

struct NoteItem: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var created: Int
}

@MainActor
@Observable
final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [NoteItem] = []
    var isLoading = false
    var errorText: String?

    /// 云端模式本地存储 key（JSON 数组）
    private let cloudKey = "qingliao_cloud_notes"
    /// 本地模式自定义地址（设置页可改；空 = 当前服务器）。
    /// 存完整 base URL，如 http://192.168.31.40:16668；空则用 auth.serverURL
    @ObservationIgnored private let baseKey = "qingliao_notes_base"

    var customBase: String {
        get { UserDefaults.standard.string(forKey: baseKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: baseKey) }
    }

    // MARK: - 读取

    func load(auth: AuthStore?, force: Bool = false) async {
        if CloudConfig.shared.isCloudMode {
            loadCloud()
            return
        }
        guard let auth, force || notes.isEmpty else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let (data, code) = try await request(auth: auth, path: "/api/notes")
            guard (200..<300).contains(code),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = j["notes"] as? [[String: Any]] else {
                errorText = "便签加载失败（\(code)）"
                return
            }
            notes = arr.compactMap { d in
                guard let id = d["id"] as? String, let text = d["text"] as? String else { return nil }
                return NoteItem(id: id, text: text, created: d["created"] as? Int ?? 0)
            }
        } catch {
            errorText = "便签加载失败"
        }
    }

    private func loadCloud() {
        guard let data = UserDefaults.standard.data(forKey: cloudKey) else { notes = []; return }
        notes = (try? JSONDecoder().decode([NoteItem].self, from: data)) ?? []
    }

    private func saveCloud() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: cloudKey)
        }
    }

    // MARK: - 新增

    func add(_ text: String, auth: AuthStore) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if CloudConfig.shared.isCloudMode {
            notes.insert(NoteItem(id: String(UUID().uuidString.prefix(10)), text: trimmed,
                                  created: Int(Date().timeIntervalSince1970)), at: 0)
            saveCloud()
            return true
        }
        errorText = nil
        do {
            let (data, code) = try await request(auth: auth, path: "/api/notes", method: "POST",
                                                 body: ["text": trimmed])
            guard (200..<300).contains(code),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let note = j["note"] as? [String: Any],
                  let id = note["id"] as? String else {
                errorText = "保存失败（\(code)）"
                return false
            }
            notes.insert(NoteItem(id: id, text: trimmed, created: note["created"] as? Int ?? 0), at: 0)
            return true
        } catch {
            errorText = "保存失败"
        }
        return false
    }

    // MARK: - 删除

    func delete(id: String, auth: AuthStore) async -> Bool {
        if CloudConfig.shared.isCloudMode {
            notes.removeAll { $0.id == id }
            saveCloud()
            return true
        }
        errorText = nil
        do {
            let (_, code) = try await request(auth: auth, path: "/api/notes/\(id)", method: "DELETE")
            guard (200..<300).contains(code) else {
                errorText = "删除失败（\(code)）"
                return false
            }
            notes.removeAll { $0.id == id }
            return true
        } catch {
            errorText = "删除失败"
        }
        return false
    }

    // MARK: - 底层请求（支持自定义 base；空 base 用 auth.serverURL）

    /// 发起便签请求：base = customBase 或 auth.serverURL。蜂窝走 AuthStore 统一分流（relay/CFStream）。
    private func request(auth: AuthStore, path: String, method: String = "GET",
                         body: [String: Any]? = nil) async throws -> (Data, Int) {
        // 复用 AuthStore 的 JSON 请求能力：临时路径改写不可行，直接用其 request() 但需要 base 覆盖——
        // AuthStore.request 固定 serverURL+path。这里走自定义 base + URLSession 直连，蜂窝降级 relay 由 AuthStore 提供。
        // 简化：本地模式地址默认即服务器，直接调 auth.json；仅当 customBase 非空且不等于服务器时才走独立 URLSession。
        let base = customBase.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || base == auth.serverURL {
            // 同服务器：走 AuthStore 统一网络层（token/蜂窝分流都现成）
            let (data, resp) = try await auth.request(path, method: method, body: body)
            return (data, resp.statusCode)
        }
        // 自定义地址：独立 URLSession 直连 + 带 token（base 规范化：去尾部斜杠防 // 拼接；无协议补 http://）
        var base = customBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "http://" + base
        }
        let url = URL(string: base + path) ?? URL(string: "https://localhost")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if !auth.token.isEmpty { req.setValue(auth.token, forHTTPHeaderField: "X-Auth-Token") }
        if let body, JSONSerialization.isValidJSONObject(body),
           let d = try? JSONSerialization.data(withJSONObject: body) {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = d
        }
        let (data, r) = try await URLSession.shared.data(for: req)
        return (data, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }
}