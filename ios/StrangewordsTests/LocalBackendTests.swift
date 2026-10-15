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
}
