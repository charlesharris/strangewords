import Foundation

/// On-device, approximate syllable count (brief.v4.md §9 / plan.v1.md §10).
/// Vowel-cluster heuristic: per word, count contiguous vowel groups, drop a
/// trailing silent "e", floor at 1. Guidance only — never blocks submission.
enum Syllables {
    static func count(_ text: String) -> Int {
        let words = text.lowercased().split { !($0.isLetter) }
        return words.reduce(0) { $0 + countWord(String($1)) }
    }

    private static func countWord(_ word: String) -> Int {
        let vowels = Set("aeiouy")
        var count = 0
        var prevVowel = false
        for ch in word {
            let isVowel = vowels.contains(ch)
            if isVowel && !prevVowel { count += 1 }
            prevVowel = isVowel
        }
        // Drop a trailing silent "e" (but never below 1).
        if word.hasSuffix("e") && count > 1 { count -= 1 }
        return max(count, word.isEmpty ? 0 : 1)
    }
}
