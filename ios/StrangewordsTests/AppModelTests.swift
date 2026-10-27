import Testing
import Foundation
@testable import Strangewords

/// AppModel state-machine tests (IOST-04). Each test is driven by the gated
/// `FakeBackend` (D-05) with `pollInterval: .zero` (D-06): the test releases every
/// response and syncs on `actionTask`/`pollTask` (D-07), never on the wall clock.
///
/// Sync rule used throughout: after resolving a terminal poll response (matched,
/// gone, turn back to you, complete) the test awaits the `pollTask` it captured
/// BEFORE resolving. After a non-terminal poll response the loop keeps running, so
/// awaiting `pollTask` would hang; the test syncs on the NEXT arrival instead.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppModelTests {
    /// Everything one test needs: a suite-named defaults container, the gated
    /// fake, its arrival walker, and a model built through the only factory.
    @MainActor
    struct Rig {
        let defaults: UserDefaults
        let cleanup: () -> Void
        let fake: FakeBackend
        let arrivals: Arrivals
        let model: AppModel

        init() {
            let isolated = makeIsolatedDefaults()
            defaults = isolated.defaults
            cleanup = isolated.cleanup
            fake = FakeBackend()
            arrivals = Arrivals(fake)
            model = makeModel(backend: fake, defaults: isolated.defaults)
        }

        /// Both identity keys are absent from this test's suite.
        var identityIsClear: Bool {
            defaults.string(forKey: TokenStore.tokenKey) == nil
                && defaults.string(forKey: TokenStore.sessionKey) == nil
        }

        /// Writes identity into this test's suite, as a previous launch would have.
        func seed(token: String?, sessionId: String?) {
            let store = TokenStore(defaults: defaults)
            store.token = token
            store.sessionId = sessionId
        }

        /// Drives begin() through an enter that matches at once.
        func beginMatched(_ view: SessionView = haikuView()) async throws {
            model.begin()
            let enter = try await arrivals.next()
            enter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: view, waitId: nil))
            await model.actionTask?.value
        }

        /// Drives begin() through an enter that must wait; returns with the first
        /// waiting poll parked and delivered.
        func beginWaiting() async throws -> FakeBackend.Pending {
            model.begin()
            let enter = try await arrivals.next()
            enter.resolve(EnterResponse(participantToken: "tok", state: "waiting", session: nil, waitId: "w"))
            await model.actionTask?.value
            return try await arrivals.next()
        }
    }

    private static let line1 = "an old silent pond"
    private static let line2 = "a frog jumps into the pond"
    private static let line3 = "splash silence again"

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

    // MARK: - The arc

    /// Entering with nobody waiting parks the model in `.waiting`; the poll loop
    /// keeps asking until a match lands, then the stranger-still-thinking poll
    /// takes over.
    @Test func beginWaitingThenPollMatches() async throws {
        let rig = Rig()
        let model = rig.model

        let firstPoll = try await rig.beginWaiting()
        #expect(model.phase == .waiting)
        #expect(firstPoll.kind == .waiting)
        #expect(firstPoll.token == "tok")

        // Still waiting: the loop asks again with no wall-clock pacing.
        firstPoll.resolve(WaitingResponse(state: "waiting", session: nil))
        let secondPoll = try await rig.arrivals.next()
        #expect(secondPoll.kind == .waiting)
        #expect(model.phase == .waiting)

        // Matched, but it is the stranger's turn first.
        let matched = haikuView(yourTurn: false)
        let waitLoop = model.pollTask
        secondPoll.resolve(WaitingResponse(state: "matched", session: matched))
        await waitLoop?.value
        #expect(model.phase == .composing(matched))
        let sessionPoll = try await rig.arrivals.next()
        #expect(sessionPoll.kind == .getSession)
        #expect(sessionPoll.id == "s1")

        await finish(model, rig.fake, rig.cleanup)
    }

    /// threshold -> connecting -> composing -> reveal -> dissolving -> dissolved,
    /// with the classic haiku, the stranger's turn in the middle, and the keepsake.
    @Test func fullArcThroughRevealAndDissolve() async throws {
        let rig = Rig()
        let model = rig.model
        let (l1, l2, l3) = (Self.line1, Self.line2, Self.line3)

        #expect(model.phase == .threshold)
        try await rig.beginMatched()
        #expect(model.phase == .composing(haikuView()))

        // Line 1 is mine; the turn passes to the stranger and polling starts.
        model.draft = l1
        model.submit()
        let firstSubmit = try await rig.arrivals.next()
        #expect(firstSubmit.kind == .submitLine)
        #expect(firstSubmit.line == 0)
        #expect(firstSubmit.text == l1)
        let afterFirst = haikuView(currentLine: 1, yourTurn: false, lines: [l1])
        firstSubmit.resolve(afterFirst)
        await model.actionTask?.value
        #expect(model.phase == .composing(afterFirst))
        #expect(model.draft == "")
        let firstPoll = try await rig.arrivals.next()
        #expect(firstPoll.kind == .getSession)

        // The stranger is still thinking: a refresh, same view, polling continues.
        firstPoll.resolve(afterFirst)
        let secondPoll = try await rig.arrivals.next()
        #expect(secondPoll.kind == .getSession)
        #expect(model.phase == .composing(afterFirst))

        // The stranger wrote line 2; the turn is back with me.
        let myTurnAgain = haikuView(currentLine: 2, yourTurn: true, lines: [l1, l2])
        let sessionLoop = model.pollTask
        secondPoll.resolve(myTurnAgain)
        await sessionLoop?.value
        #expect(model.phase == .composing(myTurnAgain))

        // Line 3 completes the poem.
        model.draft = l3
        model.submit()
        let secondSubmit = try await rig.arrivals.next()
        #expect(secondSubmit.line == 2)
        #expect(secondSubmit.text == l3)
        let complete = haikuView(status: "complete", currentLine: 3, yourTurn: false, lines: [l1, l2, l3])
        secondSubmit.resolve(complete)
        await model.actionTask?.value
        #expect(model.phase == .reveal(complete))

        // Let it go: dissolving, then dissolved with the one thing that survives.
        model.release()
        #expect(model.phase == .dissolving(complete))
        await model.actionTask?.value
        let afterRelease = await rig.fake.recordedCalls()
        #expect(afterRelease.last == .dismiss)

        model.finishDissolving()
        let expectedName = PoemNaming.coin(from: [l1, l2, l3])
        #expect(expectedName != nil)
        #expect(model.keepsake == expectedName)
        #expect(model.phase == .dissolved(.completedAndGone))
        #expect(rig.identityIsClear)

        let calls = await rig.fake.recordedCalls()
        #expect(calls == [.enter, .submitLine, .getSession, .getSession, .submitLine, .dismiss])

        await finish(model, rig.fake, rig.cleanup)
    }

    /// From a finished encounter, reset() clears the leftovers and a new begin()
    /// starts a fresh attempt.
    @Test func beginAgainStartsAFreshAttempt() async throws {
        let rig = Rig()
        let model = rig.model

        try await rig.beginMatched()
        model.draft = "leftover"
        model.leave()
        await model.actionTask?.value
        #expect(model.phase == .dissolved(.ended))

        model.reset()
        #expect(model.phase == .threshold)
        #expect(model.keepsake == nil)
        #expect(model.draft == "")
        #expect(model.submitError == nil)

        model.begin()
        #expect(model.phase == .connecting)
        let enter = try await rig.arrivals.next()
        #expect(enter.kind == .enter)
        enter.resolve(EnterResponse(participantToken: "tok2", state: "matched", session: haikuView(id: "s2"), waitId: nil))
        await model.actionTask?.value
        #expect(model.phase == .composing(haikuView(id: "s2")))
        #expect(rig.defaults.string(forKey: TokenStore.tokenKey) == "tok2")

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - Submit errors

    /// A 422 shows the server's own message and leaves the draft for editing.
    @Test func submitContentRejectedShowsServerMessage() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.draft = "x"
        model.submit()
        let submit = try await rig.arrivals.next()
        submit.fail(APIError.contentRejected("line is empty"))
        await model.actionTask?.value

        #expect(model.submitError == "line is empty")
        #expect(model.draft == "x")
        #expect(model.phase == .composing(haikuView()))
        #expect(model.submitting == false)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A 410 on submit means the stranger left.
    @Test func submitGoneDissolvesAsPartnerLeft() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.draft = Self.line1
        model.submit()
        let submit = try await rig.arrivals.next()
        submit.fail(APIError.gone)
        await model.actionTask?.value

        #expect(model.phase == .dissolved(.partnerLeft))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A stale view (409 either way) makes the model refetch and apply the result.
    @Test(arguments: [APIError.notYourTurn, APIError.wrongTurn])
    func submitStaleTurnRefetches(_ error: APIError) async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.draft = Self.line1
        model.submit()
        let submit = try await rig.arrivals.next()
        submit.fail(error)

        let refresh = try await rig.arrivals.next()
        #expect(refresh.kind == .getSession)
        #expect(refresh.id == "s1")
        let fresh = haikuView(currentLine: 2, yourTurn: true, lines: [Self.line1, Self.line2])
        refresh.resolve(fresh)
        await model.actionTask?.value
        #expect(model.phase == .composing(fresh))

        await finish(model, rig.fake, rig.cleanup)
    }

    /// Any other failure asks the writer to try again and changes nothing else.
    @Test func submitTransportErrorAsksToRetry() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.draft = Self.line1
        model.submit()
        let submit = try await rig.arrivals.next()
        submit.fail(APIError.transport)
        await model.actionTask?.value

        #expect(model.submitError == "Something slipped. Try once more.")
        #expect(model.phase == .composing(haikuView()))
        #expect(model.draft == Self.line1)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// If entering fails, the model returns to the threshold with a retry message.
    @Test func enterFailureReturnsToThreshold() async throws {
        let rig = Rig()
        let model = rig.model

        model.begin()
        let enter = try await rig.arrivals.next()
        enter.fail(APIError.transport)
        await model.actionTask?.value

        #expect(model.phase == .threshold)
        #expect(model.submitError == "Couldn't reach the quiet room. Try again.")

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - Polling edges

    /// While waiting for the stranger's line, a 410 on the poll means they left.
    @Test func partnerGoneWhileWaitingForTheirLine() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched(haikuView(yourTurn: false))

        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        let sessionLoop = model.pollTask
        poll.fail(APIError.gone)
        await sessionLoop?.value

        #expect(model.phase == .dissolved(.partnerLeft))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A wait that ends with a 410 means no one came.
    @Test func waitEndsWithNoOneCame() async throws {
        let rig = Rig()
        let model = rig.model

        let poll = try await rig.beginWaiting()
        let waitLoop = model.pollTask
        poll.fail(APIError.gone)
        await waitLoop?.value

        #expect(model.phase == .dissolved(.noOneCame))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A transient poll error keeps the wait alive: exactly one new parked poll
    /// follows, so a zero poll interval never turns into a busy loop (Pitfall 3).
    @Test func transientPollErrorKeepsPolling() async throws {
        let rig = Rig()
        let model = rig.model

        let poll = try await rig.beginWaiting()
        poll.fail(APIError.transport)
        let next = try await rig.arrivals.next()

        #expect(next.kind == .waiting)
        #expect(model.phase == .waiting)
        let calls = await rig.fake.recordedCalls()
        #expect(calls == [.enter, .waiting, .waiting])

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - Resume

    @Test func resumeWithoutTokenGoesToThreshold() async throws {
        let rig = Rig()
        let model = rig.model

        model.resume()

        #expect(model.phase == .threshold)
        let calls = await rig.fake.recordedCalls()
        #expect(calls.isEmpty)

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func resumeWithSessionAppliesIt() async throws {
        let rig = Rig()
        let model = rig.model
        rig.seed(token: "tok", sessionId: "s1")

        model.resume()
        let fetch = try await rig.arrivals.next()
        #expect(fetch.kind == .getSession)
        #expect(fetch.id == "s1")
        #expect(fetch.token == "tok")
        fetch.resolve(haikuView())
        await model.actionTask?.value

        #expect(model.phase == .composing(haikuView()))

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func resumeGoneClearsIdentity() async throws {
        let rig = Rig()
        let model = rig.model
        rig.seed(token: "tok", sessionId: "s1")

        model.resume()
        let fetch = try await rig.arrivals.next()
        fetch.fail(APIError.gone)
        await model.actionTask?.value

        #expect(rig.identityIsClear)
        #expect(model.phase == .threshold)

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func resumeWhileStillWaitingStartsPolling() async throws {
        let rig = Rig()
        let model = rig.model
        rig.seed(token: "tok", sessionId: nil)

        model.resume()
        let ask = try await rig.arrivals.next()
        #expect(ask.kind == .waiting)
        ask.resolve(WaitingResponse(state: "waiting", session: nil))
        await model.actionTask?.value

        #expect(model.phase == .waiting)
        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .waiting)

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - Leaving

    @Test func leaveMidSessionSendsLeave() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.leave()
        await model.actionTask?.value

        let calls = await rig.fake.recordedCalls()
        #expect(calls.contains(.leave))
        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// Pins today's behavior: AppModel only tells the backend when a session id
    /// exists, so a waiter who steps back out is never reported to the server.
    /// Observation carried to the SUMMARY (OBS-1); deliberately not changed here.
    @Test func leaveWhileWaitingSendsNoLeaveCall() async throws {
        let rig = Rig()
        let model = rig.model

        _ = try await rig.beginWaiting()
        model.leave()

        let calls = await rig.fake.recordedCalls()
        #expect(!calls.contains(.leave))
        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func leaveTwiceIsStable() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.leave()
        model.leave()
        await model.actionTask?.value

        let calls = await rig.fake.recordedCalls()
        #expect(calls.filter { $0 == .leave }.count <= 1)
        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func resetTwiceStaysAtThreshold() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()
        model.leave()
        await model.actionTask?.value

        model.reset()
        model.reset()

        #expect(model.phase == .threshold)
        #expect(model.keepsake == nil)
        #expect(model.draft == "")
        #expect(model.submitError == nil)

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func releaseOutsideRevealDoesNothing() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.release()

        #expect(model.phase == .composing(haikuView()))
        let calls = await rig.fake.recordedCalls()
        #expect(!calls.contains(.dismiss))

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - The robot-poet opt-in (Phase 5)

    /// Strict default OFF (D-01): a fresh install sends allowBot false, and nothing
    /// is written to the preference store by simply beginning.
    @Test func beginSendsHumansOnlyByDefault() async throws {
        let rig = Rig()
        let model = rig.model
        #expect(model.allowBot == false)

        model.begin()
        let enter = try await rig.arrivals.next()
        #expect(enter.kind == .enter)
        #expect(enter.allowBot == false)
        enter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: haikuView(), waitId: nil))
        await model.actionTask?.value

        #expect(rig.defaults.object(forKey: SettingsStore.allowBotKey) == nil)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// The opt-in crosses the wire and persists (D-01, D-02): the toggle writes the
    /// suite, begin() sends it, a bot-disclosing view lands in .composing, and the
    /// choice survives leave, reset and a brand-new model over the same defaults.
    @Test func optInTravelsAndPersists() async throws {
        let rig = Rig()
        let model = rig.model

        model.allowBot = true
        #expect(rig.defaults.bool(forKey: SettingsStore.allowBotKey) == true)

        model.begin()
        let enter = try await rig.arrivals.next()
        #expect(enter.allowBot == true)
        let botView = haikuView(partnerIsBot: true)
        enter.resolve(EnterResponse(participantToken: "tok", state: "matched", session: botView, waitId: nil))
        await model.actionTask?.value

        #expect(model.phase == .composing(botView))
        if case .composing(let s) = model.phase { #expect(s.partnerIsBot) }

        model.leave()
        await model.actionTask?.value
        model.reset()
        #expect(model.allowBot == true)
        #expect(rig.identityIsClear)

        let reread = makeModel(backend: FakeBackend(), defaults: rig.defaults)
        #expect(reread.allowBot == true)

        await finish(model, rig.fake, rig.cleanup)
    }
}
