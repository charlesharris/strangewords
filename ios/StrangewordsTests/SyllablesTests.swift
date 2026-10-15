import Testing
@testable import Strangewords

/// Characterization tests for the on-device syllable heuristic (brief.v4.md §9).
/// They pin the heuristic as it is today (IOST-01, D-12). The known misses
/// ("poem", "quiet", "rhythm", and others) are pinned in `knownMiss` at their
/// current, wrong counts. The heuristic is a soft nudge by design and is
/// deliberately not fixed in this milestone.
struct SyllablesTests {
    /// "fire" pins the trailing-silent-e drop; "" pins empty input returning 0.
    /// "happy" is the row where "y" acts as a vowel. The vowel-set mutation check
    /// (dropping "y") relies on it.
    @Test(arguments: [
        ("fire", 1),
        ("", 0),
        // Correct words.
        ("the", 1),
        ("pond", 1),
        ("jumps", 1),
        ("hour", 1),
        ("into", 2),
        ("silence", 2),
        ("again", 2),
        ("autumn", 2),
        ("lanterns", 2),
        ("happy", 2),
        ("beautiful", 3),
        // Edge inputs.
        ("hmm", 1),   // no vowels: a non-empty word floors at 1
        ("e", 1),     // the silent-e drop never goes below 1
        ("Y", 1),     // uppercase is lowercased; y counts as a vowel
        ("123", 0),   // digits are not letters
        ("😀", 0),    // emoji are not letters
    ])
    func word(_ text: String, _ expected: Int) {
        #expect(Syllables.count(text) == expected)
    }

    /// Known heuristic limits, pinned at their CURRENT (wrong) counts as
    /// characterization (D-12). Each trailing comment gives the true count and
    /// why the heuristic misses. If one of these starts failing, the heuristic
    /// changed; that is a product decision, not a test fix.
    @Test(arguments: [
        ("poem", 1),    // true 2: "oe" is one vowel cluster
        ("quiet", 1),   // true 2: "uie" is one vowel cluster
        ("rhythm", 1),  // true 2: only "y" is a vowel, one cluster
        ("table", 1),   // true 2: the trailing-e drop wrongly fires after "-le"
        ("create", 1),  // true 2: "ea" is one cluster, then the silent-e drop
        ("café", 1),    // true 2: "é" is outside the vowel set
        ("don't", 2),   // true 1: the apostrophe splits it into "don" and "t"; "t" floors at 1
    ])
    func knownMiss(_ text: String, _ current: Int) {
        #expect(Syllables.count(text) == current)
    }

    /// Multi-word summation across real poem lines, including punctuation and
    /// whitespace-only input.
    @Test(arguments: [
        ("A frog jumps into the pond", 7),
        ("An old silent pond", 5),
        ("Splash! Silence again.", 5),
        ("a frog leaps into the pond", 7),
        ("the autumn wind scatters them", 7),
        ("   ", 0),
    ])
    func haikuLine(_ text: String, _ expected: Int) {
        #expect(Syllables.count(text) == expected)
    }
}
