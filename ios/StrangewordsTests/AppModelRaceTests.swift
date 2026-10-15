import Testing
import Foundation
@testable import Strangewords

/// Stale-writer regression tests for `AppModel` (IOST-04, Phase 2 D-08 and D-09).
/// A backend response that lands after the user has left, or after a newer attempt
/// began, must never bring the session back or re-persist the participant token or
/// session id on the device.
///
/// Each test was committed red first, against an `AppModel` that lacked its guard,
/// and a separate fix commit turned it green (D-10). The red SHAs fail on purpose.
///
/// Sync rule: the stale task handle is captured BEFORE the triggering action.
/// `stopPolling()` nils `pollTask`, so capturing it after `leave()` would hand back
/// nil, `await nil?.value` would return at once, and the test would pass vacuously.
/// Tests sync on `await stale?.value` and never on the wall clock.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppModelRaceTests {
    private typealias Rig = AppModelTests.Rig

    // MARK: - Poll layer (D-08 layer 1)

    /// ROADMAP success criterion 4: the user leaves while a waiting poll is in
    /// flight, then the poll comes back "matched". The session must stay gone.
    @Test func latePollResponseAfterLeaveDoesNotResurrect() async throws {
        let rig = Rig()
        let model = rig.model

        let poll = try await rig.beginWaiting()
        let stale = model.pollTask
        model.leave()
        // yourTurn is true so even an unguarded apply() starts no further poll.
        poll.resolve(WaitingResponse(state: "matched", session: haikuView(yourTurn: true)))
        await stale?.value

        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// The same window on the session poll: a refresh that lands after leave()
    /// must not write `.composing` back.
    @Test func latePollRefreshAfterLeaveDoesNotResurrect() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched(haikuView(yourTurn: false))

        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        let stale = model.pollTask
        model.leave()
        poll.resolve(haikuView(currentLine: 1, yourTurn: false, lines: ["a"]))
        await stale?.value

        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A poll that fails with gone after leave() must not rewrite why it ended.
    @Test func lateGoneAfterLeaveKeepsEndedReason() async throws {
        let rig = Rig()
        let model = rig.model

        let poll = try await rig.beginWaiting()
        let stale = model.pollTask
        model.leave()
        poll.fail(APIError.gone)
        await stale?.value

        #expect(model.phase == .dissolved(.ended))

        await finish(model, rig.fake, rig.cleanup)
    }
}
