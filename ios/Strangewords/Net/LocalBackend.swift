import Foundation

/// A fully on-device stand-in for the backend. It matches you instantly with a
/// simulated stranger, who — when it's their turn — offers a line after a
/// thoughtful pause, then lets the poem complete and dissolve. The entire arc,
/// no server: for design iteration on a single simulator.
///
/// It mirrors the real coordination contract closely enough that `AppModel`
/// can't tell the difference: haiku form (5-7-5), round-robin authorship from a
/// start offset of 0, so the turns fall out as you → stranger → you.
actor LocalBackend: Backend {
    private let sessionId = "local-poem"
    private let you = 0
    private let targets: [Int?] = [5, 7, 5]

    /// How long the stranger "thinks" before its line appears. [TUNABLE]
    private let strangerThinkTime: TimeInterval = 1.6

    private var lines: [String] = []
    private var currentLine = 0
    private var status = "active"
    private var strangerTurnSince: Date?

    /// A few middle lines (~7 syllables) the stranger might offer, rotated so a
    /// repeated test run doesn't always read the same.
    private let strangerLines = [
        "a frog leaps into the pond",
        "the autumn wind scatters them",
        "lanterns drift down the dark stream",
        "snow settles on the still pine",
    ]
    private var strangerPick = 0

    // Round-robin over two participants from start index 0.
    private var currentAuthor: Int { currentLine % 2 }
    private var yourTurn: Bool { status == "active" && currentAuthor == you }
    private var lineCount: Int { targets.count }

    private func view() -> SessionView {
        SessionView(
            sessionId: sessionId,
            you: you,
            participantCount: 2,
            status: status,
            form: FormView(id: "haiku", targets: targets),
            currentLine: currentLine,
            currentAuthor: currentAuthor,
            yourTurn: yourTurn,
            lines: lines
        )
    }

    // MARK: - Backend

    func enter(pushToken: String?) async throws -> EnterResponse {
        // A fresh poem each time you cross the threshold.
        lines = []
        currentLine = 0
        status = "active"
        strangerTurnSince = nil
        try? await Task.sleep(for: .milliseconds(600)) // a breath at the threshold
        return EnterResponse(participantToken: "local", state: "matched", session: view(), waitId: nil)
    }

    func waiting(token: String) async throws -> WaitingResponse {
        WaitingResponse(state: "matched", session: view())
    }

    func getSession(id: String, token: String) async throws -> SessionView {
        // If the stranger is holding the poem and has had a moment to think,
        // let their line arrive. Polling (every few seconds) drives this.
        if status == "active", !yourTurn, let since = strangerTurnSince,
           Date().timeIntervalSince(since) >= strangerThinkTime {
            writeStrangerLine()
        }
        return view()
    }

    func submitLine(id: String, token: String, line: Int, text: String, idemKey: String) async throws -> SessionView {
        guard yourTurn, line == currentLine else { return view() }
        lines.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        advance()
        return view()
    }

    func leave(id: String, token: String) async {}
    func dismiss(id: String, token: String) async {}

    // MARK: - Turn machinery

    private func writeStrangerLine() {
        lines.append(strangerLines[strangerPick % strangerLines.count])
        strangerPick += 1
        advance()
    }

    private func advance() {
        currentLine += 1
        if currentLine >= lineCount {
            status = "complete"
            strangerTurnSince = nil
        } else {
            // Mark when the stranger's turn began so getSession can pace it.
            strangerTurnSince = yourTurn ? nil : Date()
        }
    }
}
