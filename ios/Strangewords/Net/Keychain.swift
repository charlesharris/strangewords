import Foundation

/// Storage for the participant token and the active sessionId — used to resume
/// the single active engagement (brief.v4.md §7).
///
/// Backed by UserDefaults: the token is a short-lived, infrastructural anonymous
/// bearer credential (scoped to one engagement, erased on dissolution), not a
/// durable secret. UserDefaults is app-sandboxed and works on unsigned
/// simulator builds, where Keychain access requires a signing entitlement and
/// otherwise fails silently. If hardware-backed storage is ever wanted on
/// signed builds, this is the single place to change.
enum TokenStore {
    private static let tokenKey = "sw.participantToken"
    private static let sessionKey = "sw.sessionId"

    static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    static var sessionId: String? {
        get { UserDefaults.standard.string(forKey: sessionKey) }
        set { UserDefaults.standard.set(newValue, forKey: sessionKey) }
    }

    /// Erase everything tying this device to an engagement.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }
}
