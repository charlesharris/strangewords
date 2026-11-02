import Testing
import Foundation
@testable import Strangewords

/// AppModel's Phase 6 trade arc (D-02), driven by the gated `FakeBackend` like
/// `AppModelTests`, and following its sync rule exactly: after a terminal poll
/// response the test awaits the `pollTask` it captured BEFORE resolving; after a
/// non-terminal one it syncs on the NEXT arrival; actions sync on `actionTask`.
/// Nothing waits on the wall clock.
///
/// The app offers or accepts only when the server's own view says `tradeOpen`; an
/// older server never sends it, so these tests also pin that nothing infers it.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppModelTradeTests {
    private typealias Rig = AppModelTests.Rig

    private static let poem = ["an old silent pond", "a frog jumps into the pond", "splash silence again"]

    /// Poem 1's reveal as the server projects it.
    private static func reveal(tradeOpen: Bool = true, youWantTrade: Bool = false,
                               partnerWantsTrade: Bool = false) -> SessionView {
        haikuView(status: "complete", currentLine: 3, yourTurn: false, lines: poem,
                  tradeOpen: tradeOpen, youWantTrade: youWantTrade,
                  partnerWantsTrade: partnerWantsTrade)
    }

    /// The opening of poem 2, with the roles swapped.
    private static func poemTwo(yourTurn: Bool) -> SessionView {
        haikuView(status: "active", currentLine: 0, yourTurn: yourTurn, lines: [], poemNumber: 2)
    }

    /// Lands the model on `view` as a reveal and returns the reveal poll's parked
    /// getSession, which exists only when the view says the trade is open.
    private static func openReveal(_ rig: Rig, _ view: SessionView) async throws -> FakeBackend.Pending {
        try await rig.beginMatched(view)
        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        #expect(poll.id == "s1")
        return poll
    }

    /// Tracer through the model: an open reveal polls, tradeBack() posts, and the
    /// server's poem 2 lands in composing. Mirrors TestTradeTracer (server).
    @Test func revealWithOpenTradeTradesBackIntoPoemTwo() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())
        #expect(model.phase == .reveal(Self.reveal()))

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        #expect(trade.kind == .tradeBack)
        #expect(trade.id == "s1")
        #expect(trade.token == "tok")
        let two = Self.poemTwo(yourTurn: true)
        trade.resolve(two)
        await model.actionTask?.value

        #expect(model.phase == .composing(two))
        let calls = await rig.fake.recordedCalls()
        #expect(calls == [.enter, .getSession, .tradeBack])

        await finish(model, rig.fake, rig.cleanup)
    }

    /// An older server never sends tradeOpen, so the reveal neither polls nor trades:
    /// nothing on the client infers it (T-06-10).
    @Test func oldServerRevealNeverPollsOrTrades() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched(Self.reveal(tradeOpen: false))
        #expect(model.phase == .reveal(Self.reveal(tradeOpen: false)))

        model.tradeBack()

        let calls = await rig.fake.recordedCalls()
        #expect(calls == [.enter])
        #expect(model.pollTask == nil)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// The partner's offer shows up on the reveal through the poll, and the poll goes on.
    @Test func partnerOfferAppearsWhileRevealPolls() async throws {
        let rig = Rig()
        let model = rig.model
        let first = try await Self.openReveal(rig, Self.reveal())

        let offered = Self.reveal(partnerWantsTrade: true)
        first.resolve(offered)
        let next = try await rig.arrivals.next()

        #expect(next.kind == .getSession)
        #expect(model.phase == .reveal(offered))

        await finish(model, rig.fake, rig.cleanup)
    }

    /// Our offer waits as a reveal showing youWantTrade; the poll then sees the
    /// partner accept and poem 2 begin.
    @Test func offerThenPollSeesPoemTwoBegin() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        let waitingOnThem = Self.reveal(youWantTrade: true)
        trade.resolve(waitingOnThem)
        await model.actionTask?.value
        #expect(model.phase == .reveal(waitingOnThem))

        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        let loop = model.pollTask
        let two = Self.poemTwo(yourTurn: false)
        poll.resolve(two)
        await loop?.value

        #expect(model.phase == .composing(two))
        let compose = try await rig.arrivals.next()
        #expect(compose.kind == .getSession)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A trade the partner declined (or that lapsed) leaves the poem on the reveal with
    /// the trade closed, and polling stops. Mirrors TestTradeDeclinedByLettingGo.
    @Test func declinedTradeStopsPollingAndKeepsTheReveal() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        trade.resolve(Self.reveal(youWantTrade: true))
        await model.actionTask?.value
        let poll = try await rig.arrivals.next()
        let loop = model.pollTask
        let closed = Self.reveal(tradeOpen: false, youWantTrade: true)
        poll.resolve(closed)
        await loop?.value

        #expect(model.phase == .reveal(closed))
        #expect(model.pollTask == nil)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A 410 at the reveal closes the trade but keeps the poem on screen; letting it
    /// go still dissolves as today, so the token stays.
    @Test func goneDuringRevealClosesTheTradeButKeepsThePoem() async throws {
        let rig = Rig()
        let model = rig.model
        let poll = try await Self.openReveal(rig, Self.reveal())

        let loop = model.pollTask
        poll.fail(APIError.gone)
        await loop?.value

        #expect(model.phase == .reveal(Self.reveal(tradeOpen: false)))
        #expect(model.pollTask == nil)
        #expect(rig.defaults.string(forKey: TokenStore.tokenKey) == "tok")

        await finish(model, rig.fake, rig.cleanup)
    }

    /// The server's 409 trade_closed (mapped to wrongTurn) means the moment passed:
    /// the reveal stays, shows we had asked, and offers no trade.
    @Test func closedTradeShowsItPassed() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        trade.fail(APIError.wrongTurn)
        await model.actionTask?.value

        #expect(model.phase == .reveal(Self.reveal(tradeOpen: false, youWantTrade: true)))
        #expect(model.pollTask == nil)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A double tap on the accept sends exactly one request: `tradeBack()` sets
    /// `trading` synchronously, so the second call returns before any network call.
    /// Poem 2 then opens normally and its poll is running (CR-01).
    @Test func secondTradeBackWhileInFlightSendsNoSecondRequest() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        model.tradeBack()   // the double tap, before any response has landed
        let trade = try await rig.arrivals.next()
        #expect(trade.kind == .tradeBack)
        let two = Self.poemTwo(yourTurn: false)
        trade.resolve(two)
        await model.actionTask?.value

        #expect(model.phase == .composing(two))
        #expect(model.pollTask != nil)
        let calls = await rig.fake.recordedCalls()
        #expect(calls.filter { $0 == .tradeBack }.count == 1)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A late 409/410 landing after poem 2 has begun never cancels poem 2's poll:
    /// `closeTrade` acts only while the reveal is on screen (CR-01).
    @Test func lateTradeFailureAfterPoemTwoBeganKeepsThePollRunning() async throws {
        let rig = Rig()
        let model = rig.model
        let revealPoll = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        #expect(trade.kind == .tradeBack)

        // The reveal poll sees poem 2 begin first (the partner's accept raced us).
        let loop = model.pollTask
        let two = Self.poemTwo(yourTurn: false)
        revealPoll.resolve(two)
        await loop?.value
        #expect(model.phase == .composing(two))
        let sessionPoll = try await rig.arrivals.next()
        #expect(sessionPoll.kind == .getSession)

        // Our own trade call then comes back 409 trade_closed (wrongTurn).
        trade.fail(APIError.wrongTurn)
        await model.actionTask?.value

        #expect(model.phase == .composing(two))
        #expect(model.pollTask != nil)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A transient failure leaves the reveal as it was, so the user may tap again.
    @Test func transientTradeFailureLeavesTheRevealOpen() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        trade.fail(APIError.transport)
        await model.actionTask?.value

        #expect(model.phase == .reveal(Self.reveal()))

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - Keepsakes (D-04)

    private static let poemTwoLines = ["lanterns drift down the dark stream",
                                       "snow settles on the still pine", "frost"]

    /// Poem 2's reveal: the trade has run its course, so no further trade is open.
    private static func poemTwoComplete() -> SessionView {
        haikuView(status: "complete", currentLine: 3, yourTurn: false,
                  lines: poemTwoLines, poemNumber: 2)
    }

    /// A full trade leaves two keepsakes: poem 1's is coined as poem 2 begins
    /// (a trade never dissolves poem 1), and poem 2's at dissolution.
    @Test func fullTradeLeavesTwoKeepsakes() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        #expect(trade.kind == .tradeBack)
        let two = Self.poemTwo(yourTurn: true)
        trade.resolve(two)
        await model.actionTask?.value

        let coinOne = try #require(PoemNaming.coin(from: Self.poem))
        #expect(model.phase == .composing(two))
        #expect(model.keepsakes == [coinOne])

        // Poem 2's last line completes it; its reveal offers no further trade.
        model.draft = Self.poemTwoLines[0]
        model.submit()
        let submit = try await rig.arrivals.next()
        #expect(submit.kind == .submitLine)
        let completeTwo = Self.poemTwoComplete()
        submit.resolve(completeTwo)
        await model.actionTask?.value
        #expect(model.phase == .reveal(completeTwo))
        #expect(model.pollTask == nil)

        model.release()
        await model.actionTask?.value
        model.finishDissolving()

        let coinTwo = try #require(PoemNaming.coin(from: Self.poemTwoLines))
        #expect(model.keepsakes == [coinOne, coinTwo])
        #expect(model.phase == .dissolved(.completedAndGone))

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A partner leaving during poem 2 still shows poem 1's name.
    @Test func partnerLeavingPoemTwoKeepsPoemOnesName() async throws {
        let rig = Rig()
        let model = rig.model
        _ = try await Self.openReveal(rig, Self.reveal())

        model.tradeBack()
        let trade = try await rig.arrivals.next()
        let two = Self.poemTwo(yourTurn: false)
        trade.resolve(two)
        await model.actionTask?.value
        #expect(model.phase == .composing(two))

        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        let loop = model.pollTask
        poll.fail(APIError.gone)
        await loop?.value

        let coinOne = try #require(PoemNaming.coin(from: Self.poem))
        #expect(model.phase == .dissolved(.partnerLeft))
        #expect(model.keepsakes == [coinOne])

        await finish(model, rig.fake, rig.cleanup)
    }

    /// A single poem leaves exactly one keepsake; reset() empties the list and
    /// begin() keeps it empty.
    @Test func aSinglePoemLeavesOneKeepsakeAndBeginClearsIt() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched(Self.reveal(tradeOpen: false))

        model.release()
        await model.actionTask?.value
        model.finishDissolving()

        let expected = try #require(PoemNaming.coin(from: Self.poem))
        #expect(model.keepsakes == [expected])
        #expect(model.phase == .dissolved(.completedAndGone))

        model.reset()
        #expect(model.keepsakes.isEmpty)

        model.begin()
        #expect(model.keepsakes.isEmpty)
        let enter = try await rig.arrivals.next()
        #expect(enter.kind == .enter)
        enter.resolve(EnterResponse(participantToken: "tok2", state: "matched",
                                    session: haikuView(id: "s2"), waitId: nil))
        await model.actionTask?.value
        #expect(model.keepsakes.isEmpty)

        await finish(model, rig.fake, rig.cleanup)
    }

    /// tradeBack() does nothing outside an open reveal we have not already asked on:
    /// no request is made and no new action task is created, so the check cannot race
    /// a call that is still on its way.
    @Test func tradeBackOnlyFromAnOpenUnaskedReveal() async throws {
        let composing = Rig()
        try await composing.beginMatched()
        let composingTask = composing.model.actionTask
        composing.model.tradeBack()
        #expect(composing.model.actionTask == composingTask)
        #expect(!(await composing.fake.recordedCalls()).contains(.tradeBack))
        await finish(composing.model, composing.fake, composing.cleanup)

        let asked = Rig()
        _ = try await Self.openReveal(asked, Self.reveal(youWantTrade: true))
        let askedTask = asked.model.actionTask
        asked.model.tradeBack()
        #expect(asked.model.actionTask == askedTask)
        #expect(!(await asked.fake.recordedCalls()).contains(.tradeBack))
        await finish(asked.model, asked.fake, asked.cleanup)
    }
}
