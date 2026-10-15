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
    static let defaultStrangerThinkTime: TimeInterval = 1.6

    /// A breath at the threshold before the match lands. [TUNABLE]
    static let defaultEnterDelay: Duration = .milliseconds(600)

    private let strangerThinkTime: TimeInterval
    private let enterDelay: Duration

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

    /// Defaults preserve the pacing the app ships with; tests pass zero so
    /// nothing waits on the wall clock (Phase 2 D-02).
    init(strangerThinkTime: TimeInterval = LocalBackend.defaultStrangerThinkTime, enterDelay: Duration = LocalBackend.defaultEnterDelay) {
        self.strangerThinkTime = strangerThinkTime
        self.enterDelay = enterDelay
    }

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
        try? await Task.sleep(for: enterDelay) // a breath at the threshold
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
        // The server checks turns before content, so the guard above stays first.
        lines.append(try Self.cleanLine(text))
        advance()
        return view()
    }

    func leave(id: String, token: String) async {}
    func dismiss(id: String, token: String) async {}

    // MARK: - Line validation

    /// Mirrors sessions.MaxLineLen (server/internal/sessions/validate.go), counted in
    /// Unicode scalars like Go runes. [TUNABLE]
    static let maxLineLength = 100

    /// Normalizes and validates a submitted line exactly as `CleanLine`
    /// (server/internal/sessions/validate.go) does, in the same order, throwing the
    /// server's own messages as `APIError.contentRejected` so `AppModel.submit` shows
    /// the same `submitError` in mock mode as against the real backend.
    ///
    /// DRIFT: the server's banned-term screener (`TestCleanLineScreens`,
    /// server/internal/sessions/content_test.go) is server-only and is not mirrored
    /// here (DRFT-01).
    static func cleanLine(_ raw: String) throws -> String {
        // Normalize to NFC first so length and character checks are stable.
        let normalized = raw.precomposedStringWithCanonicalMapping

        // Control characters are rejected, except tab, CR and LF, which count as
        // whitespace below.
        for scalar in normalized.unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" { continue }
            if scalar.properties.generalCategory == .control {
                throw APIError.contentRejected("line contains disallowed characters")
            }
        }

        // Zero-width space, non-joiner, joiner, BOM and word-joiner are stripped.
        let zeroWidth: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060]
        let stripped = normalized.unicodeScalars.filter { !zeroWidth.contains($0.value) }

        // Each run of whitespace collapses to a single space.
        var collapsed = String.UnicodeScalarView()
        var previousWasSpace = false
        for scalar in stripped {
            if scalar.properties.isWhitespace {
                if !previousWasSpace { collapsed.append(" ") }
                previousWasSpace = true
            } else {
                collapsed.append(scalar)
                previousWasSpace = false
            }
        }

        let cleaned = String(collapsed).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            throw APIError.contentRejected("line is empty")
        }
        if cleaned.unicodeScalars.count > maxLineLength {
            throw APIError.contentRejected("line exceeds maximum length")
        }
        return cleaned
    }

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
