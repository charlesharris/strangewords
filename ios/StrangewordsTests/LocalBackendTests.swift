import Testing
import Foundation
@testable import Strangewords

/// LocalBackend semantics suite (IOST-03). Each test mirrors a named Go test, cited
/// in its doc comment (D-14). Delays are passed as 0 so nothing waits on the wall
/// clock. Per D-11, divergences that `AppModel` cannot see are pinned with an
/// explicit DRIFT note rather than fixed; full parity is DRFT-01.
///
/// The suite holds no shared state: every test makes its own actor.
struct LocalBackendTests {
    /// ROADMAP Phase 2 success criterion 1: adding the delay seams must not change
    /// the pacing the app ships with in mock mode.
    @Test func defaultsMatchShippedPacing() {
        #expect(LocalBackend.defaultStrangerThinkTime == 1.6)
        #expect(LocalBackend.defaultEnterDelay == .milliseconds(600))
    }

    /// Mirrors TestFullPoemHappyPath (server/internal/gateway/gateway_test.go), pairing step.
    @Test func enterPairsImmediatelyWithAStranger() async throws {
        let backend = LocalBackend(strangerThinkTime: 0, enterDelay: .zero)

        let entered = try await backend.enter(pushToken: nil)
        #expect(entered.state == "matched")
        #expect(entered.participantToken == "local")
        #expect(entered.waitId == nil)

        let session = try #require(entered.session)
        #expect(session.status == "active")
        #expect(session.you == 0)
        #expect(session.participantCount == 2)
        #expect(session.currentLine == 0)
        #expect(session.currentAuthor == 0)
        #expect(session.yourTurn)
        #expect(session.lines.isEmpty)
        #expect(session.form.id == "haiku")
        #expect(session.form.targets == [5, 7, 5])

        let waiting = try await backend.waiting(token: "local")
        #expect(waiting.state == "matched")
        #expect(waiting.session == session)
    }
}
