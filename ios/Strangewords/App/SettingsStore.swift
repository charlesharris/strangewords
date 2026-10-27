import Foundation

/// Device preferences, a sibling of `TokenStore`. Currently one bit: whether the
/// user is willing to write with the robot poet when no stranger arrives.
///
/// This is a device preference, not identity. Points that matter:
/// - It lives outside the `sw.` key namespace that `HostIsolationTests` guards
///   (RESEARCH Pitfall 5): that namespace is for engagement identity only.
/// - `TokenStore.clear()` never touches it, so it survives every dissolution.
/// - An absent key reads `false`: strict default OFF, nobody is opted in until
///   they say so (Phase 5 D-01).
/// - `UserDefaults` use is already declared in `PrivacyInfo.xcprivacy` as
///   CA92.1 (Phase 5 D-02).
///
/// Like `TokenStore`, an instance is injected into `AppModel`: production keeps
/// `UserDefaults.standard`, tests pass a suite-named container.
struct SettingsStore {
    static let allowBotKey = "pref.allowBot"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var allowBot: Bool {
        get { defaults.bool(forKey: Self.allowBotKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.allowBotKey) }
    }
}
