import Testing
import Foundation
@testable import Strangewords

/// LocalBackend semantics suite (IOST-03). Each test mirrors a named Go test, cited
/// in its doc comment (D-14). Delays are passed as 0 so nothing waits on the wall
/// clock. Per D-11, divergences that `AppModel` cannot see are pinned with an
/// explicit DRIFT note rather than fixed; full parity is DRFT-01.
///
/// The suite holds no shared state: every test makes its own actor.
struct LocalBackendTests {
    /// ROADMAP Phase 2 success criterion 1: adding the delay seams must not change
    /// the pacing the app ships with in mock mode.
    @Test func defaultsMatchShippedPacing() {
        #expect(LocalBackend.defaultStrangerThinkTime == 1.6)
        #expect(LocalBackend.defaultEnterDelay == .milliseconds(600))
    }

    /// Mirrors TestFullPoemHappyPath (server/internal/gateway/gateway_test.go), pairing step.
    @Test func enterPairsImmediatelyWithAStranger() async throws {
        let backend = LocalBackend(strangerThinkTime: 0, enterDelay: .zero)

        let entered = try await backend.enter(pushToken: nil)
        #expect(entered.state == "matched")
        #expect(entered.participantToken == "local")
        #expect(entered.waitId == nil)

        let session = try #require(entered.session)
        #expect(session.status == "active")
        #expect(session.you == 0)
        #expect(session.participantCount == 2)
        #expect(session.currentLine == 0)
        #expect(session.currentAuthor == 0)
        #expect(session.yourTurn)
        #expect(session.lines.isEmpty)
        #expect(session.form.id == "haiku")
        #expect(session.form.targets == [5, 7, 5])

        let waiting = try await backend.waiting(token: "local")
        #expect(waiting.state == "matched")
        #expect(waiting.session == session)
    }

    // MARK: - Line validation (sessions.CleanLine)

    private static func rejection(_ message: String) -> APIError { .contentRejected(message) }

    /// A started, paired mock whose first turn is yours.
    private static func pairedBackend() async throws -> LocalBackend {
        let backend = LocalBackend(strangerThinkTime: 0, enterDelay: .zero)
        _ = try await backend.enter(pushToken: nil)
        return backend
    }

    /// Mirrors TestCleanLineAccepts (server/internal/sessions/validate_test.go), both as the
    /// static and through submitLine, where the cleaned text is what lands in the poem.
    @Test func acceptsAndCollapsesWhitespace() async throws {
        #expect(try LocalBackend.cleanLine("  an old   silent\tpond  ") == "an old silent pond")

        let backend = try await Self.pairedBackend()
        let view = try await backend.submitLine(id: "local-poem", token: "local", line: 0,
                                                text: "  an old   silent\tpond  ", idemKey: "k0")
        #expect(view.lines == ["an old silent pond"])
        #expect(view.currentLine == 1)
    }

    /// Mirrors TestCleanLineRejectsEmpty (server/internal/sessions/validate_test.go).
    @Test(arguments: ["", "   ", "\t\n", "\u{200B}\u{200B}"])
    func rejectsEmpty(input: String) {
        #expect(throws: Self.rejection("line is empty")) { try LocalBackend.cleanLine(input) }
    }

    /// Mirrors TestCleanLineRejectsTooLong (server/internal/sessions/validate_test.go):
    /// 100 is the last accepted length and 101 the first rejected.
    @Test func rejectsTooLong() throws {
        #expect(throws: Self.rejection("line exceeds maximum length")) {
            try LocalBackend.cleanLine(String(repeating: "a", count: 101))
        }
        #expect(try LocalBackend.cleanLine(String(repeating: "a", count: 100)).unicodeScalars.count == 100)
    }

    /// Mirrors TestCleanLineRejectsTooLong (server/internal/sessions/validate_test.go), whose
    /// length is counted in runes. Go counts runes, so the mock counts Unicode scalars:
    /// not graphemes (RESEARCH Pitfall 8) and not UTF-16 units. 40 ZWJ family emoji read as
    /// 40 graphemes, but the server strips the joiners and counts 120 scalars.
    @Test func countsUnicodeScalarsNotGraphemes() throws {
        let family = "\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(throws: Self.rejection("line exceeds maximum length")) {
            try LocalBackend.cleanLine(String(repeating: family, count: 40))
        }
        // 100 emoji are 200 UTF-16 units but 100 scalars: accepted. 101 are rejected.
        #expect(try LocalBackend.cleanLine(String(repeating: "\u{1F600}", count: 100)).unicodeScalars.count == 100)
        #expect(throws: Self.rejection("line exceeds maximum length")) {
            try LocalBackend.cleanLine(String(repeating: "\u{1F600}", count: 101))
        }
    }

    /// Mirrors TestCleanLineRejectsTooLong (server/internal/sessions/validate_test.go): the
    /// cap applies after NFC (RESEARCH A2). 100 x "e" + combining acute is 200 scalars as
    /// typed and 100 precomposed e-acute after normalization. Compared by scalar, because
    /// Swift String equality treats canonically equivalent strings as equal.
    @Test func normalizesToNFCBeforeCounting() throws {
        let typed = String(repeating: "e\u{0301}", count: 100)
        #expect(typed.unicodeScalars.count == 200)
        let cleaned = try LocalBackend.cleanLine(typed)
        #expect(Array(cleaned.unicodeScalars) == Array(repeating: Unicode.Scalar(0x00E9)!, count: 100))
    }

    /// Mirrors TestCleanLineRejectsControl (server/internal/sessions/validate_test.go). Tab,
    /// CR and LF are whitespace, not rejects; every other control character is.
    @Test func rejectsControlCharacters() throws {
        for input in ["hello\u{07}world", "vertical\u{0B}tab"] {
            #expect(throws: Self.rejection("line contains disallowed characters")) {
                try LocalBackend.cleanLine(input)
            }
        }
        #expect(try LocalBackend.cleanLine("a\tb\nc") == "a b c")
    }

    /// Mirrors TestCleanLineStripsZeroWidth (server/internal/sessions/validate_test.go).
    @Test func stripsZeroWidth() throws {
        #expect(try LocalBackend.cleanLine("frog\u{200B}jumps") == "frogjumps")
        #expect(try LocalBackend.cleanLine("a\u{200C}b\u{200D}c\u{FEFF}d\u{2060}e") == "abcde")
    }

    /// Mirrors TestCleanLineRejectsEmpty (server/internal/sessions/validate_test.go), through
    /// submitLine: a rejection leaves the poem exactly as it was, and the turn stays yours.
    @Test func rejectedLineLeavesThePoemUnchanged() async throws {
        let backend = try await Self.pairedBackend()
        await #expect(throws: Self.rejection("line is empty")) {
            try await backend.submitLine(id: "local-poem", token: "local", line: 0, text: "   ", idemKey: "k0")
        }
        let view = try await backend.getSession(id: "local-poem", token: "local")
        #expect(view.currentLine == 0)
        #expect(view.yourTurn)
        #expect(view.lines.isEmpty)
    }

    /// Mirrors TestCleanLineRejectsEmpty (server/internal/sessions/validate_test.go), as the
    /// user sees it. In mock mode a zero-width-only line now shows the server's message and
    /// keeps the user composing; before the fix the mock accepted it and this UX was unreachable.
    @MainActor
    @Test func mockModeSurfacesServerRejectionMessage() async throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        let model = makeModel(backend: LocalBackend(strangerThinkTime: 0, enterDelay: .zero), defaults: defaults)

        model.begin()
        await model.actionTask?.value
        model.draft = "\u{200B}"
        model.submit()
        await model.actionTask?.value

        #expect(model.submitError == "line is empty")
        if case .composing = model.phase {} else { Issue.record("expected .composing, got \(model.phase)") }

        model.leave()
        await model.actionTask?.value
        cleanup()
    }

    // MARK: - Turn order, pacing, resubmits, teardown

    private static func submit(_ backend: LocalBackend, line: Int, _ text: String, key: String = "k") async throws -> SessionView {
        try await backend.submitLine(id: "local-poem", token: "local", line: line, text: text, idemKey: key + String(line))
    }

    /// Mirrors TestRoundRobinHaikuIsABA (server/internal/sessions/policy_test.go): the authors
    /// fall you, stranger, you.
    /// Mirrors TestFullPoemHappyPath (server/internal/gateway/gateway_test.go), which walks the
    /// same three lines to a complete poem.
    @Test func roundRobinIsABA() async throws {
        let backend = LocalBackend(strangerThinkTime: 0, enterDelay: .zero)
        let first = try #require(try await backend.enter(pushToken: nil).session)
        #expect(first.currentLine == 0)
        #expect(first.currentAuthor == 0)

        let afterYours = try await Self.submit(backend, line: 0, "an old silent pond")
        #expect(afterYours.currentLine == 1)
        #expect(afterYours.currentAuthor == 1)
        #expect(!afterYours.yourTurn)

        let afterStranger = try await backend.getSession(id: "local-poem", token: "local")
        #expect(afterStranger.lines == ["an old silent pond", "a frog leaps into the pond"])
        #expect(afterStranger.currentLine == 2)
        #expect(afterStranger.currentAuthor == 0)
        #expect(afterStranger.yourTurn)

        let done = try await Self.submit(backend, line: 2, "splash silence again")
        #expect(done.status == "complete")
        #expect(done.currentLine == 3)
        #expect(done.lines.count == 3)
    }

    /// Mirrors TestFullPoemHappyPath (server/internal/gateway/gateway_test.go): the stranger's
    /// turn is held until it writes. With a 3600 s think time the line is not due, so this
    /// proves the hold without waiting on the wall clock.
    @Test func strangerHoldsThePoemUntilThinkTimePasses() async throws {
        let backend = LocalBackend(strangerThinkTime: 3600, enterDelay: .zero)
        _ = try await backend.enter(pushToken: nil)
        _ = try await Self.submit(backend, line: 0, "an old silent pond")

        let view = try await backend.getSession(id: "local-poem", token: "local")
        #expect(view.lines.count == 1)
        #expect(!view.yourTurn)
        #expect(view.currentLine == 1)
    }

    /// Mirrors TestTurnOrderViolations (server/internal/gateway/gateway_test.go). A wrong line
    /// index, or a submit during the stranger's turn, appends nothing.
    ///
    /// DRIFT: the server answers 409 (wrong_turn / not_your_turn) where the mock returns the
    /// current view. AppModel refetches on those errors anyway, so it cannot tell (D-11, DRFT-01).
    @Test func wrongLineOrOutOfTurnIsIgnored() async throws {
        let backend = LocalBackend(strangerThinkTime: 3600, enterDelay: .zero)
        _ = try await backend.enter(pushToken: nil)

        let wrongLine = try await Self.submit(backend, line: 1, "wrong line")
        #expect(wrongLine.lines.isEmpty)
        #expect(wrongLine.currentLine == 0)

        _ = try await Self.submit(backend, line: 0, "an old silent pond")
        let outOfTurn = try await Self.submit(backend, line: 1, "not my turn")
        #expect(outOfTurn.lines == ["an old silent pond"])
        #expect(outOfTurn.currentLine == 1)
        #expect(!outOfTurn.yourTurn)
    }

    /// Mirrors TestIdempotentResubmit (server/internal/gateway/gateway_test.go). A second
    /// submit of line 0 with the same key never adds a second line.
    ///
    /// DRIFT: the server replays the original response verbatim from its idempotency cache;
    /// the mock ignores idemKey and rejects the repeat on turn order alone. AppModel.submit
    /// mints a fresh key per call, so AppModel cannot see the difference (D-11, DRFT-01).
    @Test func resubmitDoesNotDuplicate() async throws {
        let backend = LocalBackend(strangerThinkTime: 3600, enterDelay: .zero)
        _ = try await backend.enter(pushToken: nil)

        _ = try await backend.submitLine(id: "local-poem", token: "local", line: 0, text: "first words here", idemKey: "dupe")
        _ = try await backend.submitLine(id: "local-poem", token: "local", line: 0, text: "different text", idemKey: "dupe")

        let view = try await backend.getSession(id: "local-poem", token: "local")
        #expect(view.lines == ["first words here"])
        #expect(view.currentLine == 1)
    }

    /// Mirrors TestLeaveDissolves (server/internal/gateway/gateway_test.go): after leave, reads
    /// and writes report gone. The poem's lines are erased with it.
    @Test func leaveDissolvesAndErasesThePoem() async throws {
        let backend = LocalBackend(strangerThinkTime: 3600, enterDelay: .zero)
        _ = try await backend.enter(pushToken: nil)
        _ = try await Self.submit(backend, line: 0, "an old silent pond")

        await backend.leave(id: "local-poem", token: "local")

        await #expect(throws: APIError.gone) {
            try await backend.getSession(id: "local-poem", token: "local")
        }
        await #expect(throws: APIError.gone) {
            try await Self.submit(backend, line: 1, "too late")
        }
    }

    /// Mirrors TestFullPoemHappyPath (server/internal/gateway/gateway_test.go), dismiss-by-all
    /// step: once a finished poem is dismissed, a fetch is gone.
    @Test func dismissAfterCompletionDissolves() async throws {
        let backend = LocalBackend(strangerThinkTime: 0, enterDelay: .zero)
        _ = try await backend.enter(pushToken: nil)
        _ = try await Self.submit(backend, line: 0, "an old silent pond")
        _ = try await backend.getSession(id: "local-poem", token: "local")
        let done = try await Self.submit(backend, line: 2, "splash silence again")
        #expect(done.status == "complete")

        await backend.dismiss(id: "local-poem", token: "local")

        await #expect(throws: APIError.gone) {
            try await backend.getSession(id: "local-poem", token: "local")
        }
    }

    /// Mirrors TestFullPoemHappyPath (server/internal/gateway/gateway_test.go), dismiss-by-all
    /// step: a new encounter after teardown starts a fresh poem with nothing left over.
    @Test func enterAfterTeardownStartsAFreshPoem() async throws {
        let backend = LocalBackend(strangerThinkTime: 0, enterDelay: .zero)
        _ = try await backend.enter(pushToken: nil)
        _ = try await Self.submit(backend, line: 0, "an old silent pond")
        await backend.dismiss(id: "local-poem", token: "local")

        let fresh = try #require(try await backend.enter(pushToken: nil).session)
        #expect(fresh.status == "active")
        #expect(fresh.currentLine == 0)
        #expect(fresh.lines.isEmpty)
        #expect(fresh.yourTurn)
    }
}
