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
