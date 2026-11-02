import Foundation

/// A name coined from a finished poem — the single durable thing the dissolution
/// leaves behind (the "keepsake" layer, see docs/STATUS.md). The poem itself is
/// still let go; what remains is one strange coined name.
///
/// Fully **deterministic** and **on-device**: the seed is derived from the poem's
/// own text, so the same poem always coins the same name, and nothing leaves the
/// device (honoring the anonymity / nothing-kept model — see brief.v4.md).
struct CoinedName: Equatable {
    /// Only the name is shown, with its lead (Phase 6 D-05).
    let lead: String   // soft framing line, e.g. "It's gone now — but it left a name:"
    let name: String   // "Silent Pond Porter"
}

enum PoemNaming {

    /// Coin a name from the poem's lines, or `nil` if there aren't enough real
    /// words to work with (the caller falls back to the plain farewell).
    static func coin(from lines: [String]) -> CoinedName? {
        var pool = contentWords(in: lines)
        guard !pool.isEmpty else { return nil }

        var rng = SeededGenerator(seed: fnv1a(lines.joined(separator: "\n").lowercased()))
        pool.shuffle(using: &rng)
        var draw = Draw(pool)

        // One-word poems can only fill the solo patterns; richer poems get the
        // full catalogue. Which pattern you get is a deliberate surprise, drawn
        // from the poem's own seed.
        let coiner = (pool.count >= 2 ? coiners : soloCoiners).randomElement(using: &rng)!
        let made = coiner(&draw, &rng)
        let lead = leads.randomElement(using: &rng)!
        return CoinedName(lead: lead, name: made)
    }

    // MARK: - Word extraction

    /// The poem's "content" words: letters-only tokens, three or more characters,
    /// stopwords removed, de-duplicated in order of first appearance, title-cased.
    private static func contentWords(in lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in lines {
            for raw in line.lowercased().split(whereSeparator: { !$0.isLetter }) {
                let w = String(raw)
                if w.count < 3 || stopwords.contains(w) { continue }
                if seen.insert(w).inserted { out.append(titlecase(w)) }
            }
        }
        return out
    }

    private static func titlecase(_ w: String) -> String {
        guard let first = w.first else { return w }
        return first.uppercased() + w.dropFirst()
    }

    // MARK: - The catalogue

    /// A name from a word source and the seeded RNG. A coiner may pull one or
    /// several words; `Draw` cycles the (shuffled, distinct) pool so successive
    /// pulls differ as long as the poem offered more than one word.
    private typealias Coiner = (_ d: inout Draw, _ r: inout SeededGenerator) -> String

    private static let beerStyles = ["Stout", "Porter", "IPA", "Pale Ale", "Saison",
                                     "Lager", "Bitter", "Amber Ale", "Pilsner"]

    /// Patterns that read best with two or more distinct words.
    ///
    /// Entries keep their pre-D-05 order and count even where name shapes now
    /// repeat, because the catalogue's weights and seeded draw order are pinned
    /// by the PoemNamingTests goldens, and merging duplicates would change names.
    private static let coiners: [Coiner] = [
        { d, r in let s = one(beerStyles, &r)
                  return "\(d.next()) \(d.next()) \(s)" },
        { d, _ in "\(d.next()) & \(d.next())" },
        { d, _ in "\(d.next()) \(d.next())" },
        { d, _ in "\(d.next()) \(d.next())" },
        { d, r in "\(d.next()) No. \(Int.random(in: 1...31, using: &r))" },
        { d, _ in "\(d.next()) \(d.next())" },
        { d, _ in "\(d.next()) \(d.next()) Reserve" },
        { d, _ in "\(d.next()) & \(d.next())" },
        { d, _ in "\(d.next()) \(d.next())" },
        { d, r in Bool.random(using: &r) ? "\(d.next()) \(d.next())"
                                         : "The \(d.next())s" },
        { d, _ in "The \(d.next()) \(d.next())" },
        { d, _ in "\(d.next()) \(d.next())" },
        { d, _ in "\(d.next()) \(d.next())" },
        { d, _ in "\(d.next()) \(d.next()) Light" },
        { d, _ in "\(d.next()) \(d.next())" },
        { d, _ in "\(d.next())'s \(d.next())" },
    ]

    /// Fallbacks for a poem that yielded a single usable word. Same order-and-count
    /// rule as `coiners` above.
    private static let soloCoiners: [Coiner] = [
        { d, r in let s = one(beerStyles, &r)
                  return "\(d.next()) \(s)" },
        { d, _ in "\(d.next())" },
        { d, r in "\(d.next()) No. \(Int.random(in: 1...31, using: &r))" },
        { d, _ in "The \(d.next())" },
        { d, _ in "\(d.next()) Light" },
        { d, _ in "\(d.next())" },
        { d, _ in "\(d.next())" },
    ]

    private static let leads = [
        "It's gone now — but it left a name behind.",
        "The poem dissolved. This is what it named:",
        "Nothing was kept, except a name:",
        "On its way out, it named something:",
        "One strange word stayed behind:",
        "Gone — but not before it became",
    ]

    private static func one(_ xs: [String], _ r: inout SeededGenerator) -> String {
        xs.randomElement(using: &r)!
    }

    // MARK: - Words to avoid promoting into a name

    private static let stopwords: Set<String> = [
        "the", "and", "but", "for", "nor", "yet", "with", "without", "into", "onto",
        "from", "off", "out", "over", "under", "upon", "about", "above", "below",
        "between", "through", "near", "are", "was", "were", "been", "being", "its",
        "this", "that", "these", "those", "you", "your", "yours", "him", "her",
        "his", "hers", "she", "they", "them", "their", "theirs", "our", "ours",
        "who", "whom", "which", "what", "when", "where", "while", "then", "than",
        "all", "any", "some", "each", "every", "not", "too", "very", "just", "yes",
        "will", "would", "can", "could", "shall", "should", "may", "might", "must",
        "does", "did", "done", "has", "have", "had", "get", "got", "let", "lets",
        "until", "still", "here", "there", "such", "only", "also", "even", "ever",
        "anymore", "twice", "once", "again", "almost", "always", "never", "maybe",
    ]
}

// MARK: - Deterministic randomness

/// A seedable SplitMix64 generator. Swift's default RNG is per-process random, so
/// we roll our own to keep coining reproducible from the poem's text alone.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// FNV-1a over UTF-8 — a stable hash for the seed (unlike `Hasher`, which is
/// randomized each launch).
private func fnv1a(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return h
}

/// Cycles a (pre-shuffled, de-duplicated) word pool. Successive `next()` calls
/// return distinct words until the pool is exhausted, then wrap.
private struct Draw {
    private let words: [String]
    private var i = 0
    init(_ words: [String]) { self.words = words }
    mutating func next() -> String {
        defer { i += 1 }
        return words[i % words.count]
    }
}
