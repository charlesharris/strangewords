import Testing
import Foundation
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

    // MARK: - partnerIsBot (Phase 5 D-04)

    /// Shaped exactly like Go's json.Marshal of sessions.View for a robot-poet
    /// session: every View key, `partnerIsBot` present because it is true.
    private static let botSessionJSON = """
    {"sessionId":"s-bot","you":0,"participantCount":2,"status":"active",\
    "form":{"id":"haiku","targets":[5,7,5]},"currentLine":1,"currentAuthor":0,\
    "yourTurn":true,"lines":["An old silent pond"],"partnerIsBot":true}
    """

    /// The same View for a human session: the server omits `partnerIsBot` when
    /// false (`omitempty`), so the key is simply absent.
    private static let humanSessionJSON = """
    {"sessionId":"s-human","you":1,"participantCount":2,"status":"active",\
    "form":{"id":"haiku","targets":[5,7,5]},"currentLine":0,"currentAuthor":1,\
    "yourTurn":true,"lines":[]}
    """

    @Test func decodesPartnerIsBotWhenPresent() throws {
        let view = try JSONDecoder().decode(SessionView.self, from: Data(Self.botSessionJSON.utf8))
        #expect(view.partnerIsBot == true)
        #expect(view.sessionId == "s-bot")
        #expect(view.you == 0)
        #expect(view.participantCount == 2)
        #expect(view.status == "active")
        #expect(view.form == FormView(id: "haiku", targets: [5, 7, 5]))
        #expect(view.currentLine == 1)
        #expect(view.currentAuthor == 0)
        #expect(view.yourTurn == true)
        #expect(view.lines == ["An old silent pond"])
    }

    /// An old server, or any human session, omits the key. Plain synthesized
    /// Codable would throw keyNotFound and strand the whole session decode.
    @Test func partnerIsBotDefaultsFalseWhenAbsent() throws {
        let view = try JSONDecoder().decode(SessionView.self, from: Data(Self.humanSessionJSON.utf8))
        #expect(view.partnerIsBot == false)
        #expect(view.sessionId == "s-human")
        #expect(view.you == 1)
    }

    /// Existing construction sites (TestSupport, LocalBackend, this file) omit the argument.
    @Test func memberwiseDefaultsPartnerIsBotFalse() {
        #expect(session(form: Self.haiku, currentLine: 0).partnerIsBot == false)
    }
}
