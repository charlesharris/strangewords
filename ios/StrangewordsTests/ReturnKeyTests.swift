import Testing
import Foundation
@testable import Strangewords

/// Pins quick-261029-l7l's return-key contract at the model seam ComposeView
/// forwards to. ComposeView's `.onChange(of: model.draft)` is stood in for by
/// direct `model.draftChanged(from:to:)` calls; XCUITest is out of scope for this
/// milestone. Every test syncs on `actionTask`, parked FakeBackend arrivals or
/// synchronous model state, never on the wall clock.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ReturnKeyTests {
    private typealias Rig = AppModelTests.Rig

    private static let line = "an old silent pond"

    // MARK: - Tracer

    @Test func returnKeyOffersTheLineLikeTheButton() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.draft = Self.line
        model.draftChanged(from: Self.line, to: Self.line + "\n")

        #expect(model.draft == Self.line)
        try #require(model.submitting)

        let offer = try await rig.arrivals.next()
        #expect(offer.kind == .submitLine)
        #expect(offer.line == 0)
        #expect(offer.text == Self.line)

        let after = haikuView(currentLine: 1, yourTurn: false, lines: [Self.line])
        offer.resolve(after)
        await model.actionTask?.value

        #expect(model.phase == .composing(after))
        #expect(model.draft == "")

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - Guards

    @Test func returnOnABlankDraftDoesNothing() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        for blank in ["", "   "] {
            model.draft = blank
            model.draftChanged(from: blank, to: blank + "\n")
            #expect(model.draft == blank, "draft changed for \(blank.debugDescription)")
            try #require(!model.submitting)
            #expect(model.submitError == nil)
            model.returnKeyPressed()
            try #require(!model.submitting)
        }

        let calls = await rig.fake.recordedCalls()
        #expect(calls == [.enter])
        #expect(model.phase == .composing(haikuView()))

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func returnWhileALineIsInFlightSendsOnlyOne() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        let line = Self.line
        model.draft = line
        model.returnKeyPressed()   // the onSubmit backstop
        let first = model.actionTask
        let offer = try await rig.arrivals.next()
        #expect(offer.kind == .submitLine)

        model.draftChanged(from: line, to: line + "\n")   // the onChange intercept, same press
        model.returnKeyPressed()
        #expect(model.draft == line)
        try #require(model.actionTask == first)
        #expect(model.submitting)

        offer.resolve(haikuView(currentLine: 1, yourTurn: false, lines: [line]))
        await first?.value

        let calls = await rig.fake.recordedCalls()
        #expect(calls.filter { $0 == .submitLine }.count == 1)

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func returnOnTheirTurnDoesNothing() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched(haikuView(yourTurn: false))

        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        let stale = model.pollTask

        model.draft = "x"
        model.draftChanged(from: "x", to: "x\n")
        #expect(model.draft == "x")
        #expect(!model.submitting)
        let calls = await rig.fake.recordedCalls()
        #expect(!calls.contains(.submitLine))

        model.leave()
        await model.actionTask?.value
        poll.resolve(haikuView(yourTurn: false))
        await stale?.value

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func pastedLinesNeverOfferAndReachTheWireAsOneLine() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        let pasted = "an old silent pond\na frog jumps in"
        let joined = "an old silent pond a frog jumps in"
        model.draftChanged(from: "", to: pasted)
        #expect(model.draft == joined)
        try #require(!model.submitting)

        model.submit()   // the button
        let offer = try await rig.arrivals.next()
        #expect(offer.kind == .submitLine)
        #expect(offer.text == joined)
        offer.resolve(haikuView(currentLine: 1, yourTurn: false, lines: [joined]))
        await model.actionTask?.value

        await finish(model, rig.fake, rig.cleanup)
    }

    @Test func canSubmitIsSharedByButtonAndReturn() async throws {
        let rig = Rig()
        let model = rig.model

        model.draft = Self.line
        #expect(!model.canSubmit)   // threshold

        try await rig.beginMatched()
        #expect(model.draft == Self.line)
        #expect(model.canSubmit)
        model.draft = ""
        #expect(!model.canSubmit)
        model.draft = "   "
        #expect(!model.canSubmit)
        model.draft = Self.line
        #expect(model.canSubmit)

        model.submit()
        #expect(!model.canSubmit)   // in flight
        let offer = try await rig.arrivals.next()
        offer.resolve(haikuView(currentLine: 1, yourTurn: false, lines: [Self.line]))
        await model.actionTask?.value

        #expect(model.draft == "")
        model.draft = "x"
        #expect(!model.canSubmit)   // their turn

        await finish(model, rig.fake, rig.cleanup)
    }
}
