import Foundation

/// The Compose field's input rule (quick-261029-l7l).
///
/// A poem line is one line, so the keyboard must never let a line break into the
/// draft. The field is a vertical-axis `TextField`, which inserts return as a line
/// break instead of calling `onSubmit`; `AppModel.draftChanged(from:to:)` feeds
/// every edit through `edit(from:to:)` to decide what it meant.
///
/// - Only an edit whose sole inserted Character is one line break is the return
///   key. It leaves the draft exactly as it was. A paste never offers: offering a
///   line is irreversible and shared with a stranger, so only an unambiguous
///   return press may trigger it. If autocorrect lands together with the line
///   break, the edit is read as a paste and the line is not offered, which is a
///   non-destructive outcome (a second return offers it).
/// - Every other line break becomes one space (a run becomes one space), matching
///   the server's whitespace collapse, so the stored line is the line the user saw
///   and pasted lines don't fuse.
/// - VT, FF and NEL would otherwise be rejected by the cleaners as control
///   characters.
/// - This does not replace `sessions.CleanLine` or `LocalBackend.cleanLine`, which
///   remain the hard rule.
enum DraftInput {
    /// What one field edit means: the text the draft should hold (never containing
    /// a line break) and whether the edit was the return key.
    struct Edit: Equatable {
        let draft: String
        let returnPressed: Bool
    }

    /// Replaces each maximal run of line-break Characters (LF, CR, CRLF, VT, FF,
    /// NEL, U+2028, U+2029) with exactly one space. Everything else, tabs and NBSP
    /// included, passes through unchanged.
    static func removingLineBreaks(_ text: String) -> String {
        var out = ""
        var inBreak = false
        for ch in text {
            if ch.isNewline {
                if !inBreak { out.append(" ") }
                inBreak = true
            } else {
                out.append(ch)
                inBreak = false
            }
        }
        return out
    }

    /// Classifies one edit by a common-prefix/common-suffix diff over Characters
    /// (so CRLF counts as one). A lone inserted line break is a return press and
    /// leaves the draft as `old`; anything else is a plain edit with its line
    /// breaks replaced.
    static func edit(from old: String, to new: String) -> Edit {
        let a = Array(old)
        let b = Array(new)
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        let inserted = b[p..<(b.count - s)]
        if inserted.count == 1, let only = inserted.first, only.isNewline {
            return Edit(draft: removingLineBreaks(old), returnPressed: true)
        }
        return Edit(draft: removingLineBreaks(new), returnPressed: false)
    }
}
