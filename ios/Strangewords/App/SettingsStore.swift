import Foundation

/// Device preferences, a sibling of `TokenStore`. Currently two: whether the user
/// is willing to write with the robot poet when no stranger arrives, and which
/// scenery (`Themes` id) they chose to write in.
///
/// This is a device preference, not identity. Points that matter:
/// - It lives outside the `sw.` key namespace that `HostIsolationTests` guards
///   (RESEARCH Pitfall 5): that namespace is for engagement identity only.
/// - `TokenStore.clear()` never touches it, so it survives every dissolution.
/// - An absent `allowBot` key reads `false`: strict default OFF, nobody is opted
///   in until they say so (Phase 5 D-01).
/// - An absent `themeID` key reads `nil`, which callers resolve to the registry
///   default, nature. The scenery never leaves the device.
/// - `UserDefaults` use is already declared in `PrivacyInfo.xcprivacy` as
///   CA92.1 (Phase 5 D-02).
///
/// Like `TokenStore`, an instance is injected into `AppModel`: production keeps
/// `UserDefaults.standard`, tests pass a suite-named container.
struct SettingsStore {
    static let allowBotKey = "pref.allowBot"
    static let themeKey = "pref.theme"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var allowBot: Bool {
        get { defaults.bool(forKey: Self.allowBotKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.allowBotKey) }
    }

    /// The chosen scenery's `Themes` id; nil when the user has never chosen (absent
    /// key), which callers resolve to the registry default, nature.
    var themeID: String? {
        get { defaults.string(forKey: Self.themeKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.themeKey) }
    }
}
