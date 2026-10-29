import Testing
import Foundation
@testable import Strangewords

/// Pins the user's scenery choice (quick-261029-k47): a device preference beside the
/// robot-poet opt-in, never identity, never sent to the server. An absent key means
/// nature.
struct ThemeSelectionTests {
    // MARK: - SettingsStore

    /// The choice is a preference, not identity: same `pref.` namespace as the
    /// robot-poet opt-in, outside the `sw.` namespace HostIsolationTests polices.
    @Test func settingsStoreThemeKeyIsAPreferenceNotIdentity() {
        #expect(SettingsStore.themeKey == "pref.theme")
        #expect(SettingsStore.themeKey.hasPrefix("pref."))
        #expect(!SettingsStore.themeKey.hasPrefix("sw."))
        #expect(SettingsStore.themeKey != SettingsStore.allowBotKey)
    }

    @Test func settingsStoreThemeIsAbsentByDefaultAndRoundTrips() {
        let (defaultsA, cleanupA) = makeIsolatedDefaults()
        let (defaultsB, cleanupB) = makeIsolatedDefaults()
        defer { cleanupA(); cleanupB() }
        let a = SettingsStore(defaults: defaultsA)
        let b = SettingsStore(defaults: defaultsB)

        // Never chosen: nothing stored, nothing read back.
        #expect(a.themeID == nil)
        #expect(defaultsA.object(forKey: SettingsStore.themeKey) == nil)

        a.themeID = "sci-fi"
        #expect(a.themeID == "sci-fi")
        #expect(defaultsA.string(forKey: SettingsStore.themeKey) == "sci-fi")
        #expect(b.themeID == nil)
        // The two preferences are independent.
        #expect(a.allowBot == false)

        // Dissolution clears identity, never the preference.
        let tokens = TokenStore(defaults: defaultsA)
        tokens.token = "tok"
        tokens.sessionId = "sess"
        tokens.clear()
        #expect(tokens.token == nil)
        #expect(a.themeID == "sci-fi")
    }

    // MARK: - AppModel

    @MainActor
    @Test func freshModelPaintsNatureAndWritesNothing() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let model = makeModel(backend: FakeBackend(), defaults: defaults)
        #expect(model.themeID == "nature")
        #expect(defaults.object(forKey: SettingsStore.themeKey) == nil)
    }

    @MainActor
    @Test func chosenSceneryPersistsAcrossRelaunch() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let model = makeModel(backend: FakeBackend(), defaults: defaults)
        model.themeID = "fantasy"
        #expect(defaults.string(forKey: SettingsStore.themeKey) == "fantasy")

        // The choice is a preference: it survives leaving and resetting.
        model.leave()
        model.reset()
        #expect(model.themeID == "fantasy")

        let relaunched = makeModel(backend: FakeBackend(), defaults: defaults)
        #expect(relaunched.themeID == "fantasy")
        // Exactly what RootView paints at a normal launch.
        #expect(Themes.resolve(devOverride: nil, forced: nil, preferred: relaunched.themeID).id == "fantasy")
    }

    @MainActor
    @Test func unknownStoredSceneryFallsBackToNature() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        defaults.set("retired-scenery", forKey: SettingsStore.themeKey)
        let model = makeModel(backend: FakeBackend(), defaults: defaults)
        #expect(model.themeID == "nature")
    }

    // MARK: - Copy

    @Test func sceneryCopyIsPinned() {
        #expect(SettingsView.themeTitle == "scenery")
        #expect(SettingsView.themeHelper == "the world your poem is written in. only you see it.")
    }

    // MARK: - Registry

    @Test func registryIdsAndNamesArePinned() {
        #expect(Themes.all.map(\.id) == ["nature", "sci-fi", "fantasy"])
        #expect(Themes.all.map(\.name) == ["nature", "sci-fi", "fantasy"])
        #expect(Themes.default.id == "nature")
    }

    // MARK: - Precedence: dev chip > SW_FORCE_THEME > stored choice > nature

    @Test func resolveFallsBackToNatureWhenNothingValidIsChosen() {
        #expect(Themes.resolve(devOverride: nil, forced: nil, preferred: nil).id == "nature")
        #expect(Themes.resolve(devOverride: nil, forced: nil, preferred: "retired-scenery").id == "nature")
        #expect(Themes.resolve(devOverride: "bogus", forced: "bogus", preferred: "bogus").id == "nature")
    }

    @Test func storedSceneryPaintsWhenNothingOverridesIt() {
        for theme in Themes.all {
            #expect(Themes.resolve(devOverride: nil, forced: nil, preferred: theme.id).id == theme.id,
                    "stored \(theme.id) did not paint")
        }
    }

    @Test func forcedSceneryBeatsTheStoredChoice() {
        #expect(Themes.resolve(devOverride: nil, forced: "sci-fi", preferred: "fantasy").id == "sci-fi")
        // An unknown forced id falls through to the stored choice.
        #expect(Themes.resolve(devOverride: nil, forced: "bogus", preferred: "fantasy").id == "fantasy")
    }

    @Test func devCycleBeatsForcedAndStored() {
        #expect(Themes.resolve(devOverride: "fantasy", forced: "sci-fi", preferred: "nature").id == "fantasy")
        #expect(Themes.resolve(devOverride: "bogus", forced: "sci-fi", preferred: "nature").id == "sci-fi")
    }

    // MARK: - Voice

    private func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    /// Every visible scenery string is lowercase, calm, and free of the cold
    /// vocabulary the robot-poet copy avoids (Phase 5 T-05-13) plus the
    /// engineering word "theme".
    @Test func sceneryCopyKeepsTheVoice() {
        let banned: Set<String> = ["bot", "ai", "assistant", "chatbot", "algorithm", "queue",
                                   "searching", "matched", "theme"]
        let visible = [SettingsView.themeTitle, SettingsView.themeHelper] + Themes.all.map(\.name)
        for s in visible {
            #expect(s == s.lowercased(), "not lowercase: \(s)")
            #expect(!s.contains("!"), "exclamation in: \(s)")
            #expect(words(s).isDisjoint(with: banned), "cold vocabulary in: \(s)")
        }
    }
}
