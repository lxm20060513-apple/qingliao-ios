import Foundation
import Observation

// MARK: - 便签 Store（v3.0.8 看板便签）
// 本地 AI 模式：存 NAS 后端（/api/notes，存储目录可在设置自定义——NAS 绝对路径，默认 /data）；
//              请求带 X-Notes-Dir 头，后端写到指定目录的 notes.json。
// 云端模式：存 App 本地 UserDefaults。双模式共用 UI，数据层按模式分流。

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
    /// 本地模式自定义存储目录（NAS 绝对路径，设置页可改；空 = 服务器默认 /data）
    @ObservationIgnored private let dirKey = "qingliao_notes_dir"

    var customDir: String {
        get { UserDefaults.standard.string(forKey: dirKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: dirKey) }
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

    // MARK: - 底层请求（走 AuthStore 统一网络层 + X-Notes-Dir 头）

    private func request(auth: AuthStore, path: String, method: String = "GET",
                         body: [String: Any]? = nil) async throws -> (Data, Int) {
        // 复用 AuthStore 的复用网络层：需附加 X-Notes-Dir 头，直接走 request 并注入头。
        // AuthStore.request 不开放自定义 header——这里用直接 URLSession + token（蜂窝下
        // 便签读写量小，短请求可接受；与 App 其它轻接口一致）。
        let base = auth.serverURL
        let url = URL(string: base + path) ?? URL(string: "https://localhost")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if !auth.token.isEmpty { req.setValue(auth.token, forHTTPHeaderField: "X-Auth-Token") }
        // v3.0.8 fix：便签存储目录（NAS 绝对路径）——默认不带头（后端用 /data）
        let dir = customDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dir.isEmpty {
            req.setValue(dir, forHTTPHeaderField: "X-Notes-Dir")
        }
        if let body, JSONSerialization.isValidJSONObject(body),
           let d = try? JSONSerialization.data(withJSONObject: body) {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = d
        }
        let (data, r) = try await URLSession.shared.data(for: req)
        return (data, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }
}