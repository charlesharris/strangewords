import Foundation

/// RED scaffolding: compiles, behaves wrongly (never persists).
struct SettingsStore {
    static let allowBotKey = "pref.allowBot"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var allowBot: Bool { get { false } nonmutating set {} }
}
