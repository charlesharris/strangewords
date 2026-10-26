import Testing
import Foundation
@testable import Strangewords

/// Defaults-preservation proof for every seam this phase adds (ROADMAP Phase 2
/// success criterion 1, IOST-05, D-01 through D-03): the app built with all
/// defaults must behave exactly as it did before the seams existed.
///
/// The hosted test process runs with `SW_LOCAL_MOCK=1` and `SW_API_BASE` pointing
/// at a dead port, so nothing here reads `ProcessInfo`; API defaults go through
/// the pure `APIClient.resolveBase(environment:)`. Nothing here writes to
/// `UserDefaults.standard`.
struct SeamDefaultsTests {
    /// The one sanctioned direct construction in a test file: it passes `tokenStore:`
    /// explicitly and leaves `pollInterval` defaulted, which is the point.
    @MainActor
    @Test func appModelPollsEveryThreeSecondsByDefault() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let model = AppModel(backend: FakeBackend(), tokenStore: TokenStore(defaults: defaults))
        #expect(AppModel.defaultPollInterval == .seconds(3))
        #expect(model.pollInterval == .seconds(3))
    }

    /// Installed builds resume by these exact strings; renaming them orphans a token.
    @Test func tokenStoreKeysAreUnchanged() {
        #expect(TokenStore.tokenKey == "sw.participantToken")
        #expect(TokenStore.sessionKey == "sw.sessionId")
    }

    /// Production keeps the single shared container. Reads `.defaults` only.
    @Test func tokenStoreDefaultsToStandard() {
        #expect(TokenStore().defaults === UserDefaults.standard)
    }

    /// Empty, round-trip, clear, and adjacency: two stores over different suites
    /// never see each other's keys.
    @Test func tokenStoreIsolatesSuites() {
        let (defaultsA, cleanupA) = makeIsolatedDefaults()
        let (defaultsB, cleanupB) = makeIsolatedDefaults()
        defer { cleanupA(); cleanupB() }
        let a = TokenStore(defaults: defaultsA)
        let b = TokenStore(defaults: defaultsB)

        // Empty: a fresh suite reads nil, and clear() on it does nothing.
        #expect(a.token == nil)
        #expect(a.sessionId == nil)
        a.clear()
        #expect(a.token == nil)
        #expect(a.sessionId == nil)

        // Round trip, with the neighbour still empty.
        a.token = "tok-a"
        a.sessionId = "sess-a"
        #expect(a.token == "tok-a")
        #expect(a.sessionId == "sess-a")
        #expect(b.token == nil)
        #expect(b.sessionId == nil)

        // Clearing one suite leaves the other untouched.
        b.token = "tok-b"
        a.clear()
        #expect(a.token == nil)
        #expect(a.sessionId == nil)
        #expect(b.token == "tok-b")
    }

    @Test func apiBaseDefaultsToProduction() {
        #expect(APIClient.resolveBase(environment: [:]).absoluteString == "https://api.strangewords.app")
        #expect(APIClient.resolveBase(environment: ["SW_API_BASE": "http://127.0.0.1:9"]).absoluteString == "http://127.0.0.1:9")
    }

    @Test func apiClientUsesInjectedBase() async {
        let client = APIClient(base: URL(string: "http://x:1")!)
        let base = await client.base
        #expect(base.absoluteString == "http://x:1")
    }

    /// The anonymity posture: an ephemeral configuration (no persistent cookies or
    /// cache) with the 15-second request timeout, not a process-wide shared session.
    @Test func defaultSessionIsEphemeralWithFifteenSecondTimeout() {
        let configuration = APIClient.makeDefaultSession().configuration
        #expect(configuration.timeoutIntervalForRequest == 15)
        #expect(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
    }
}
