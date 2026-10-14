import Testing
@testable import Strangewords

/// Characterization tests for the on-device syllable heuristic (brief.v4.md §9).
/// They pin the heuristic as it is today. Known misses ("poem", "quiet",
/// "rhythm") are deliberately not pinned here; Phase 2 IOST-01 owns them.
struct SyllablesTests {
    /// "fire" pins the trailing-silent-e drop; "" pins empty input returning 0.
    @Test(arguments: [
        ("fire", 1),
        ("", 0),
    ])
    func word(_ text: String, _ expected: Int) {
        #expect(Syllables.count(text) == expected)
    }

    /// Multi-word summation across a real poem line. Phase 2 appends rows here.
    @Test(arguments: [
        ("A frog jumps into the pond", 7),
    ])
    func haikuLine(_ text: String, _ expected: Int) {
        #expect(Syllables.count(text) == expected)
    }
}
