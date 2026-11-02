import Testing
@testable import Strangewords

/// Pins the Compose field's edit rule (quick-261029-l7l): a lone inserted line
/// break is the return key and leaves the draft unchanged; every other line break
/// becomes a space and never offers.
struct DraftInputTests {
    private func edit(_ old: String, _ new: String) -> DraftInput.Edit {
        DraftInput.edit(from: old, to: new)
    }

    @Test func typingAndDeletingPassThrough() {
        #expect(edit("an old", "an old p") == .init(draft: "an old p", returnPressed: false))
        #expect(edit("an old pond", "an old pon") == .init(draft: "an old pon", returnPressed: false))
    }

    @Test func returnAtTheEndIsAPressAndLeavesTheDraft() {
        #expect(edit("an old silent pond", "an old silent pond\n")
                == .init(draft: "an old silent pond", returnPressed: true))
    }

    @Test func returnMidLineIsAPressAndLeavesTheDraft() {
        #expect(edit("an old pond", "an old\n pond") == .init(draft: "an old pond", returnPressed: true))
    }

    @Test func returnOverASelectionKeepsTheSelectedText() {
        #expect(edit("an old silent pond", "an old \n pond")
                == .init(draft: "an old silent pond", returnPressed: true))
    }

    @Test func returnOnABlankDraftIsAPressWithNothingToOffer() {
        #expect(edit("", "\n") == .init(draft: "", returnPressed: true))
        #expect(edit("   ", "   \n") == .init(draft: "   ", returnPressed: true))
    }

    @Test func carriageReturnAndCRLFArePresses() {
        #expect(edit("a", "a\r") == .init(draft: "a", returnPressed: true))
        #expect(edit("a", "a\r\n") == .init(draft: "a", returnPressed: true))
    }

    @Test func pastedLineBreaksBecomeOneSpace() {
        #expect(edit("", "an old silent pond\na frog jumps in")
                == .init(draft: "an old silent pond a frog jumps in", returnPressed: false))
        #expect(edit("", "a\n\n\r\nb") == .init(draft: "a b", returnPressed: false))
    }

    @Test func pasteEndingInALineBreakIsNotAPress() {
        #expect(edit("", "an old silent pond\n") == .init(draft: "an old silent pond ", returnPressed: false))
    }

    @Test func autocorrectFoldedIntoReturnIsNotAPress() {
        #expect(edit("an old pnd", "an old pond\n") == .init(draft: "an old pond ", returnPressed: false))
    }

    @Test func everyUnicodeLineBreakBecomesASpace() {
        let breaks = ["\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]
        for lb in breaks {
            let scalars = lb.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "+")
            #expect(DraftInput.removingLineBreaks("a" + lb + "b") == "a b", "U+\(scalars)")
        }
        #expect(DraftInput.removingLineBreaks("a\tb") == "a\tb")
        #expect(DraftInput.removingLineBreaks("a\u{A0}b") == "a\u{A0}b")
    }

    @Test func noEditEverLeavesALineBreak() {
        #expect(edit("abc\n", "abc") == .init(draft: "abc", returnPressed: false))
        #expect(edit("a\nb", "a\nb\n") == .init(draft: "a b", returnPressed: true))
        #expect(edit("a", "a\na") == .init(draft: "a a", returnPressed: false))

        let pairs: [(String, String)] = [
            ("an old", "an old p"), ("an old pond", "an old pon"),
            ("an old silent pond", "an old silent pond\n"), ("an old pond", "an old\n pond"),
            ("an old silent pond", "an old \n pond"), ("", "\n"), ("   ", "   \n"),
            ("a", "a\r"), ("a", "a\r\n"), ("", "an old silent pond\na frog jumps in"),
            ("", "a\n\n\r\nb"), ("", "an old silent pond\n"), ("an old pnd", "an old pond\n"),
            ("abc\n", "abc"), ("a\nb", "a\nb\n"), ("a", "a\na"),
            ("", "a\u{0B}b\u{2028}c\u{85}d"),
        ]
        for (old, new) in pairs {
            let result = edit(old, new)
            let hasBreak = result.draft.contains { $0.isNewline }
            #expect(!hasBreak, "line break left after \(old.debugDescription) -> \(new.debugDescription)")
        }
    }
}
