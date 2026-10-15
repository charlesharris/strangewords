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

    // MARK: - Action layer (D-08 layer 2, D-09 scenario 2)

    /// The user leaves while a submitted line is in flight. The server's answer
    /// must neither re-persist the session id nor bring `.composing` back.
    @Test func lateSubmitResponseAfterLeaveDoesNotResurrect() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.draft = "x"
        model.submit()
        let submit = try await rig.arrivals.next()
        #expect(submit.kind == .submitLine)
        let stale = model.actionTask
        model.leave()
        submit.resolve(haikuView(currentLine: 1, yourTurn: false, lines: ["x"]))
        await stale?.value

        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// The user backs out while the enter request is still in flight.
    @Test func lateEnterResponseAfterLeaveDoesNotResurrect() async throws {
        let rig = Rig()
        let model = rig.model

        model.begin()
        let enter = try await rig.arrivals.next()
        #expect(enter.kind == .enter)
        let stale = model.actionTask
        model.leave()
        enter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: haikuView(), waitId: nil))
        await stale?.value

        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// Attempt one is abandoned and attempt two begins; attempt one's response
    /// lands first and must be ignored, while attempt two's still applies.
    @Test func staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain() async throws {
        let rig = Rig()
        let model = rig.model

        model.begin()
        let firstEnter = try await rig.arrivals.next()
        let staleFirst = model.actionTask
        model.leave()
        model.reset()
        model.begin()
        let secondEnter = try await rig.arrivals.next()
        #expect(secondEnter.kind == .enter)

        firstEnter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: haikuView(id: "old"), waitId: nil))
        await staleFirst?.value
        #expect(model.phase == .connecting)

        secondEnter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: haikuView(id: "new"), waitId: nil))
        await model.actionTask?.value
        #expect(model.phase == .composing(haikuView(id: "new")))
        #expect(rig.defaults.string(forKey: TokenStore.sessionKey) == "new")

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A cold-launch resume is still fetching when the user starts a new attempt;
    /// the old session's answer must not overwrite the new attempt.
    @Test func lateResumeResponseAfterBeginIsIgnored() async throws {
        let rig = Rig()
        let model = rig.model
        rig.seed(token: "tok", sessionId: "old")

        model.resume()
        let fetch = try await rig.arrivals.next()
        #expect(fetch.kind == .getSession)
        let stale = model.actionTask
        model.begin()
        let enter = try await rig.arrivals.next()
        #expect(enter.kind == .enter)

        fetch.resolve(haikuView(id: "old"))
        await stale?.value
        #expect(model.phase == .connecting)

        enter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: haikuView(id: "s2"), waitId: nil))
        await model.actionTask?.value
        #expect(model.phase == .composing(haikuView(id: "s2")))
        #expect(rig.defaults.string(forKey: TokenStore.sessionKey) == "s2")

        await finish(model, rig.fake, rig.cleanup)
    }
}
