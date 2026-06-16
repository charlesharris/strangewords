import Foundation
import Security

/// Minimal Keychain wrapper for the participant token — the only secret the
/// client holds. It is scoped to the single active engagement and cleared on
/// dissolution (brief.v4.md §7). The sessionId is not secret and lives in
/// UserDefaults alongside it for resume.
enum TokenStore {
    private static let service = "com.strangewords.app"
    private static let account = "participantToken"
    private static let sessionKey = "sw.sessionId"

    static var token: String? {
        get { keychainRead() }
        set {
            if let newValue { keychainWrite(newValue) } else { keychainDelete() }
        }
    }

    static var sessionId: String? {
        get { UserDefaults.standard.string(forKey: sessionKey) }
        set { UserDefaults.standard.set(newValue, forKey: sessionKey) }
    }

    /// Erase everything tying this device to an engagement.
    static func clear() {
        token = nil
        sessionId = nil
    }

    // MARK: - Keychain primitives

    private static func keychainWrite(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainRead() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
