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
///
/// An instance is injected into `AppModel` (Phase 2 D-01): production keeps the
/// default `UserDefaults.standard`, while tests pass a suite-named container so
/// no test ever writes identity into the app's shared defaults.
struct TokenStore {
    static let tokenKey = "sw.participantToken"
    static let sessionKey = "sw.sessionId"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var token: String? {
        get { defaults.string(forKey: Self.tokenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.tokenKey) }
    }

    var sessionId: String? {
        get { defaults.string(forKey: Self.sessionKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.sessionKey) }
    }

    /// Erase everything tying this device to an engagement.
    func clear() {
        defaults.removeObject(forKey: Self.tokenKey)
        defaults.removeObject(forKey: Self.sessionKey)
    }
}
