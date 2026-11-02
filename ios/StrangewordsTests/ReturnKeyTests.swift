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
}
