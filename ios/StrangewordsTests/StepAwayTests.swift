import Testing
import Foundation
@testable import Strangewords

/// Pins the Compose escape copy and the leave contract for the 2026-10-27
/// stuck-session todo (.planning/todos/pending/2026-10-27-add-leave-affordance-to-compose.md).
/// Every test syncs on `actionTask`, `pollTask` or parked FakeBackend arrivals,
/// never on the wall clock. The confirmation dialog's destructive button is
/// stood in for by a direct `model.leave()` call; XCUITest is out of scope for
/// this milestone.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct StepAwayTests {
    private typealias Rig = AppModelTests.Rig

    // MARK: - Copy

    @Test func copyIsPinned() {
        #expect(StepAway.label == "step away")
        #expect(StepAway.accessibilityHint == "Asks before letting this unfinished poem go. It will not be saved.")
        #expect(StepAway.confirmTitle == "step away from this poem?")
        #expect(StepAway.confirmMessage == "the poem will dissolve unfinished and won't come back")
        #expect(StepAway.confirmAction == "step away")
        #expect(StepAway.stayAction == "stay with the poem")
    }

    // MARK: - Their turn (the reported trap)

    @Test func stepAwayWhileTheirTurnSendsLeaveAndDissolves() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched(haikuView(currentLine: 1, yourTurn: false, lines: ["an old silent pond"]))

        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        let stale = model.pollTask
        model.leave()
        await model.actionTask?.value
        poll.resolve(haikuView(currentLine: 1, yourTurn: false, lines: ["an old silent pond"]))
        await stale?.value

        let calls = await rig.fake.recordedCalls()
        #expect(model.phase == .dissolved(.ended))
        #expect(calls.filter { $0 == .leave }.count == 1)
        #expect(rig.identityIsClear)
        #expect(model.keepsake == nil)
        #expect(model.pollTask == nil)

        await finish(model, rig.fake, rig.cleanup)
    }
}
