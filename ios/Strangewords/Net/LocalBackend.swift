import Foundation

/// A fully on-device stand-in for the backend. It matches you instantly with a
/// simulated stranger, who — when it's their turn — offers a line after a
/// thoughtful pause, then lets the poem complete and dissolve. The entire arc,
/// no server: for design iteration on a single simulator.
///
/// It mirrors the real coordination contract closely enough that `AppModel`
/// can't tell the difference: haiku form (5-7-5), round-robin authorship from a
/// start offset of 0, so the turns fall out as you → stranger → you.
///
/// Like the server, `leave`, `leaveWait` and `dismiss` dissolve the poem: its lines
/// are erased and later reads and writes report `APIError.gone` until the next
/// `enter`.
///
/// An opted-in `enter` (`allowBot: true`) mirrors the server's robot-poet arc: it
/// answers waiting, keeps answering waiting for `botWindow`, then matches with a
/// session whose `partnerIsBot` is true (server: `TestBotFallbackTracer`).
///
/// DRIFT: the mock's robot poet writes the scripted `strangerLines` rather than
/// the server's `server/internal/poet` output (D-11, DRFT-01).
/// DRIFT: an opted-in mock user always waits the full window, because the mock has
/// no human pool to race; the server races an atomic LREM claim against LPOP so a
/// human arriving first wins.
/// DRIFT: the server also drops waiters who stop polling (`StaleWaiterAfter`) when an
/// arriver pops them; the mock has no queue or other arrivers, so there is nothing
/// to drop.
/// DRIFT: the mock starts with your turn, where the server picks `StartIndex` at
/// random, so the robot poet may write first there. Poem 2 starts with the stranger,
/// as on the server after a trade (the start seat moves one later).
///
/// Phase 6 trade back (`tradeBack`) mirrors the server's offer-and-accept arc
/// (`TestTradeTracer`, `TestBotTradesBack` in server/internal/gateway/trade_test.go):
/// the complete view reports `tradeOpen` while a later poem exists, offering and
/// accepting are the same call, and the call that makes every participant ask begins
/// poem 2 in the same session with the roles swapped (D-03).
/// DRIFT: the mock human stranger always offers to trade back after its think time at
/// poem 1's reveal, so one simulator can design the accept state; a real stranger may
/// never offer.
/// DRIFT: the mock reuses `strangerThinkTime` for the stranger's offer and acceptance,
/// where the server's robot poet uses `BotThink` and humans answer when they answer.
actor LocalBackend: Backend {
    private let sessionId = "local-poem"
    private let you = 0
    private let targets: [Int?] = [5, 7, 5]

    /// How long the stranger "thinks" before its line appears. [TUNABLE]
    static let defaultStrangerThinkTime: TimeInterval = 1.6

    /// A breath at the threshold before the match lands. [TUNABLE]
    static let defaultEnterDelay: Duration = .milliseconds(600)

    /// How long an opted-in user waits before the robot poet arrives. Mirrors
    /// config.BotWindow (SW_BOT_WAIT_SECONDS) on the server. [TUNABLE]
    static let defaultBotWindow: TimeInterval = 25

    private let strangerThinkTime: TimeInterval
    private let enterDelay: Duration
    private let botWindow: TimeInterval

    private var lines: [String] = []
    private var currentLine = 0
    private var status = "active"
    private var strangerTurnSince: Date?

    /// Mirrors sessions.MaxPoems: poems in one encounter. [TUNABLE]
    static let maxPoems = 2

    /// Which poem of the encounter this is, from 1.
    private var poemNumber = 1
    /// You have offered (or accepted); the stranger has not answered yet.
    private var youWantTrade = false
    /// The stranger has offered (or accepted).
    private var strangerWantsTrade = false
    /// When the reveal began, to pace the stranger's offer.
    private var revealSince: Date?
    /// When you asked, to pace the stranger's acceptance.
    private var tradeSince: Date?

    /// A few middle lines (~7 syllables) the stranger might offer, rotated so a
    /// repeated test run doesn't always read the same.
    private let strangerLines = [
        "a frog leaps into the pond",
        "the autumn wind scatters them",
        "lanterns drift down the dark stream",
        "snow settles on the still pine",
    ]
    private var strangerPick = 0

    /// Five-syllable lines for the opening and closing slots of a poem the stranger
    /// writes in (poem 2, after the roles swap). Each scores 5 under `Syllables.count`.
    private let strangerShortLines = [
        "soft rain on the roof",
        "a lone crow calls out",
        "the old bell rings twice",
        "cold wind through bare trees",
    ]
    private var strangerShortPick = 0

    /// True once the wait ended with the robot poet; surfaced as `partnerIsBot`.
    private var partnerIsBot = false
    /// Set while an opted-in user is waiting; nil when matched or not waiting.
    private var waitingSince: Date?

    /// Defaults preserve the pacing the app ships with; tests pass zero so
    /// nothing waits on the wall clock (Phase 2 D-02).
    init(strangerThinkTime: TimeInterval = LocalBackend.defaultStrangerThinkTime,
         enterDelay: Duration = LocalBackend.defaultEnterDelay,
         botWindow: TimeInterval = LocalBackend.defaultBotWindow) {
        self.strangerThinkTime = strangerThinkTime
        self.enterDelay = enterDelay
        self.botWindow = botWindow
    }

    // Round-robin over two participants from start index 0, with poem N starting one
    // seat later: Session.AuthorOf's poem offset (D-03).
    private var currentAuthor: Int { (currentLine + poemNumber - 1) % 2 }
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
            lines: lines,
            partnerIsBot: partnerIsBot,
            poemNumber: poemNumber,
            tradeOpen: tradeOpen,
            youWantTrade: youWantTrade,
            partnerWantsTrade: strangerWantsTrade
        )
    }

    /// A later poem exists and this one is finished.
    private var tradeOpen: Bool { status == "complete" && poemNumber < Self.maxPoems }

    // MARK: - Backend

    func enter(pushToken: String?, allowBot: Bool) async throws -> EnterResponse {
        // A fresh poem each time you cross the threshold.
        lines = []
        currentLine = 0
        status = "active"
        strangerTurnSince = nil
        partnerIsBot = false
        waitingSince = nil
        resetTrade()
        poemNumber = 1
        try? await Task.sleep(for: enterDelay) // a breath at the threshold
        guard allowBot else {
            return EnterResponse(participantToken: "local", state: "matched", session: view(), waitId: nil)
        }
        // Opted in: no stranger yet. waiting() ends the wait with the robot poet.
        waitingSince = Date()
        return EnterResponse(participantToken: "local", state: "waiting", session: nil, waitId: "local-wait")
    }

    func waiting(token: String) async throws -> WaitingResponse {
        if status == "dissolved" { throw APIError.gone } // the server's 410 once the token ref is gone
        if let since = waitingSince {
            guard Date().timeIntervalSince(since) >= botWindow else {
                return WaitingResponse(state: "waiting", session: nil)
            }
            waitingSince = nil
            partnerIsBot = true
        }
        return WaitingResponse(state: "matched", session: view())
    }

    func getSession(id: String, token: String) async throws -> SessionView {
        if status == "dissolved" { throw APIError.gone }
        // If the stranger is holding the poem and has had a moment to think,
        // let their line arrive. Polling (every few seconds) drives this.
        if status == "active", !yourTurn, let since = strangerTurnSince,
           Date().timeIntervalSince(since) >= strangerThinkTime {
            writeStrangerLine()
        }
        settleTrade()
        return view()
    }

    func submitLine(id: String, token: String, line: Int, text: String, idemKey: String) async throws -> SessionView {
        if status == "dissolved" { throw APIError.gone }
        guard yourTurn, line == currentLine else { return view() }
        // The server checks turns before content, so the guard above stays first.
        lines.append(try Self.cleanLine(text))
        advance()
        return view()
    }

    func tradeBack(id: String, token: String) async throws -> SessionView {
        if status == "dissolved" { throw APIError.gone }
        guard tradeOpen else { throw APIError.wrongTurn } // the server's 409 trade_closed
        if youWantTrade { return view() } // an idempotent repeat
        youWantTrade = true
        if strangerWantsTrade {
            beginNextPoem()
        } else {
            tradeSince = Date()
        }
        return view()
    }

    func leave(id: String, token: String) async { dissolve() }
    func leaveWait(token: String) async { dissolve() }
    func dismiss(id: String, token: String) async { dissolve() }

    /// Dissolution erases the poem, as on the server (TestLeaveDissolves).
    private func dissolve() {
        status = "dissolved"
        lines = []
        strangerTurnSince = nil
        waitingSince = nil
        resetTrade()
    }

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
        // The 5-syllable slots take a 5-syllable line, so poem 2's opener and closer
        // fit; poem 1's stranger only ever writes the 7-syllable middle line.
        if targets[currentLine] == 5 {
            lines.append(strangerShortLines[strangerShortPick % strangerShortLines.count])
            strangerShortPick += 1
        } else {
            lines.append(strangerLines[strangerPick % strangerLines.count])
            strangerPick += 1
        }
        advance()
    }

    /// At a tradeable reveal the mock stranger answers after its think time: it
    /// accepts your offer, or (a human stranger only) offers first. The robot poet
    /// accepts but never offers, like the server (D-06).
    private func settleTrade() {
        guard tradeOpen else { return }
        let now = Date()
        if youWantTrade, !strangerWantsTrade, let since = tradeSince,
           now.timeIntervalSince(since) >= strangerThinkTime {
            beginNextPoem()
        } else if !partnerIsBot, !youWantTrade, !strangerWantsTrade, let since = revealSince,
                  now.timeIntervalSince(since) >= strangerThinkTime {
            strangerWantsTrade = true
        }
    }

    /// Poem N+1 in the same encounter: the poem-level fields reset in place, as on the
    /// server (Session.BeginNextPoem), and the roles swap through `currentAuthor`.
    private func beginNextPoem() {
        poemNumber += 1
        lines = []
        currentLine = 0
        status = "active"
        youWantTrade = false
        strangerWantsTrade = false
        tradeSince = nil
        revealSince = nil
        strangerTurnSince = yourTurn ? nil : Date()
    }

    private func resetTrade() {
        youWantTrade = false
        strangerWantsTrade = false
        revealSince = nil
        tradeSince = nil
    }

    private func advance() {
        currentLine += 1
        if currentLine >= lineCount {
            status = "complete"
            strangerTurnSince = nil
            revealSince = Date()
        } else {
            // Mark when the stranger's turn began so getSession can pace it.
            strangerTurnSince = yourTurn ? nil : Date()
        }
    }
}
