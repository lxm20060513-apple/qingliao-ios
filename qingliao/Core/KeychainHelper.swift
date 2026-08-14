import Foundation
import Security

/// v2.0.88：Face ID 登录凭据（Keychain 存储，安全保存服务器/用户名/密码）
/// 仅当设置「Face ID 登录」开启时写入；关闭开关即清除。
enum FaceIDStore {

    struct Credential: Codable {
        let server: String
        let username: String
        let password: String
    }

    private static let service = "com.qingliao.app"
    private static let account = "login_credential"

    /// 保存凭据（已存在则更新）
    static func save(server: String, username: String, password: String) {
        guard !username.isEmpty, !password.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(
            Credential(server: server, username: username, password: password)
        ) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    /// 读取凭据（无凭据返回 nil）
    static func load() -> Credential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    /// 清除凭据（关闭开关时调用）
    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
