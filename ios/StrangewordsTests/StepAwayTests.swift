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

    private func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    private var allCopy: [String] {
        [StepAway.label, StepAway.accessibilityHint, StepAway.confirmTitle,
         StepAway.confirmMessage, StepAway.confirmAction, StepAway.stayAction]
    }

    /// The app's chrome voice is lowercase ("step back out", "let it go"). The
    /// accessibility hint is sentence case, like RevealView's, and is excluded.
    @Test func visibleCopyIsLowercase() {
        let visible = [StepAway.label, StepAway.confirmTitle, StepAway.confirmMessage,
                       StepAway.confirmAction, StepAway.stayAction]
        for s in visible {
            #expect(s == s.lowercased(), "not lowercase: \(s)")
        }
    }

    @Test func copyKeepsTheRitualVoice() {
        let banned: Set<String> = ["bot", "ai", "assistant", "chatbot", "algorithm", "queue",
                                   "searching", "matched", "session", "quit", "exit", "cancel", "leave"]
        for s in allCopy {
            #expect(words(s).isDisjoint(with: banned), "cold word in: \(s)")
        }
    }

    /// The same copy is shown with human and robot-poet partners (Phase 5 D-04 / T-05-13).
    @Test func copyFitsEitherPartner() {
        let partners: Set<String> = ["stranger", "someone", "robot", "person"]
        for s in allCopy {
            #expect(words(s).isDisjoint(with: partners), "names a partner in: \(s)")
        }
    }

    // MARK: - Your turn

    @Test func stepAwayMidDraftNeverOffersTheLine() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched()

        model.draft = "half a line"
        model.leave()
        await model.actionTask?.value

        let calls = await rig.fake.recordedCalls()
        #expect(calls.contains(.leave))
        #expect(!calls.contains(.submitLine))
        #expect(model.phase == .dissolved(.ended))
        #expect(rig.identityIsClear)
        #expect(model.keepsake == nil)

        await finish(model, rig.fake, rig.cleanup)
    }

    // MARK: - Relaunch

    @Test func relaunchAfterSteppingAwayStartsAtTheThreshold() async throws {
        let rig = Rig()
        let model = rig.model
        try await rig.beginMatched(haikuView(yourTurn: false))

        let poll = try await rig.arrivals.next()
        #expect(poll.kind == .getSession)
        let stale = model.pollTask

        // Before stepping away, a relaunch over these defaults would resume the trap.
        let before = TokenStore(defaults: rig.defaults)
        #expect(before.token == "tok")
        #expect(before.sessionId == "s1")

        model.leave()
        await model.actionTask?.value
        poll.resolve(haikuView(yourTurn: false))
        await stale?.value

        let relaunchFake = FakeBackend()
        let relaunched = makeModel(backend: relaunchFake, defaults: rig.defaults)
        relaunched.resume()

        let relaunchCalls = await relaunchFake.recordedCalls()
        #expect(relaunched.phase == .threshold)
        #expect(relaunched.actionTask == nil)
        #expect(relaunchCalls.isEmpty)
        #expect(rig.identityIsClear)

        await finish(relaunched, relaunchFake, {})
        await finish(model, rig.fake, rig.cleanup)
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
