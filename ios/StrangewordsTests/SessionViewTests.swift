import Testing
@testable import Strangewords

/// Pins the 5/7/5 nudge thresholds that ComposeView reads through
/// `SessionView.currentTarget` (IOST-01). The user-visible hint text is a private
/// View method and is out of scope here.
struct SessionViewTests {
    private static let haiku = FormView(id: "haiku", targets: [5, 7, 5])

    private func session(form: FormView, currentLine: Int) -> SessionView {
        SessionView(sessionId: "s", you: 0, participantCount: 2, status: "active",
                    form: form, currentLine: currentLine, currentAuthor: 0,
                    yourTurn: true, lines: [])
    }

    @Test(arguments: [(0, 5), (1, 7), (2, 5)])
    func haikuTargetForLine(_ line: Int, _ target: Int) {
        #expect(session(form: Self.haiku, currentLine: line).currentTarget == target)
    }

    /// Past the last line, and a negative index, both mean no nudge.
    @Test(arguments: [3, -1])
    func noTargetOutsideTheForm(_ line: Int) {
        #expect(session(form: Self.haiku, currentLine: line).currentTarget == nil)
    }

    /// A null target entry (free verse) means no nudge for that line.
    @Test func nullTargetEntryMeansNoNudge() {
        let free = FormView(id: "free", targets: [nil, 7])
        #expect(session(form: free, currentLine: 0).currentTarget == nil)
        #expect(session(form: free, currentLine: 1).currentTarget == 7)
    }

    /// The classic haiku's lines count exactly their line's target.
    @Test func classicHaikuMeetsEachTarget() {
        let lines = ["An old silent pond", "A frog jumps into the pond", "Splash! Silence again."]
        for (index, line) in lines.enumerated() {
            let target = session(form: Self.haiku, currentLine: index).currentTarget
            #expect(Syllables.count(line) == target, "line \(index): \(line)")
        }
    }
}
