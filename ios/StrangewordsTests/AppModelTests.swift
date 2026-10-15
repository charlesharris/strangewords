import Testing
import Foundation
@testable import Strangewords

/// AppModel state-machine tests (IOST-04). Each test is driven by the gated
/// `FakeBackend` (D-05) with `pollInterval: .zero` (D-06): the test releases every
/// response and syncs on `actionTask`/`pollTask` (D-07), never on the wall clock.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppModelTests {
    /// Tracer: begin() crosses the injected TokenStore, the defaulted init, the
    /// action task handle and the gated fake, and lands in `.composing`.
    @Test func beginMatchedLandsInComposing() async throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        let fake = FakeBackend()
        let arrivals = Arrivals(fake)
        let model = makeModel(backend: fake, defaults: defaults)

        model.begin()
        #expect(model.phase == .connecting)

        let enter = try await arrivals.next()
        #expect(enter.kind == .enter)
        enter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: haikuView(), waitId: nil))
        await model.actionTask?.value

        #expect(model.phase == .composing(haikuView()))
        #expect(defaults.string(forKey: TokenStore.tokenKey) == "tok")
        #expect(defaults.string(forKey: TokenStore.sessionKey) == "s1")
        #expect(UserDefaults.standard.string(forKey: TokenStore.tokenKey) == nil)
        #expect(UserDefaults.standard.string(forKey: TokenStore.sessionKey) == nil)
        let calls = await fake.recordedCalls()
        #expect(calls == [.enter])

        await finish(model, fake, cleanup)
    }
}
