import Testing
@testable import Strangewords

/// Pins keepsake naming (IOST-02, D-13): the same poem always coins the same
/// name, and the hash (FNV-1a) and PRNG (SplitMix64) behind it stay stable.
///
/// The goldens were captured on the harness's pinned simulator: iPhone 16,
/// iOS 18.6 (22G86), Xcode 16.4 (16F6). `PoemNaming.coin` leans on the stdlib's
/// seeded `shuffle(using:)` and `randomElement(using:)`, which Apple documents as
/// free to change between Swift releases, so a golden failure right after an
/// Xcode or iOS update may be stdlib drift and not a code regression
/// (RESEARCH Pitfall 5). Re-capture a golden only with a cited reason in the
/// commit and the Phase 4 ledger; never to quiet a failure.
struct PoemNamingTests {
    struct Golden: Sendable, CustomTestStringConvertible {
        let label: String
        let lines: [String]
        let lead: String
        let name: String
        let kind: String
        var testDescription: String { label }
    }

    static let classicHaiku = ["an old silent pond", "a frog jumps into the pond", "splash silence again"]

    static let goldens: [Golden] = [
        Golden(label: "classic haiku", lines: classicHaiku,
               lead: "One strange word stayed behind:", name: "Old Splash", kind: "an aged cheese"),
        Golden(label: "repeated identical lines", lines: ["moon", "moon", "moon"],
               lead: "The poem dissolved. This is what it named:", name: "Moon No. 5", kind: "a perfume"),
        Golden(label: "single word (solo catalogue)", lines: ["moon"],
               lead: "Gone — but not before it became", name: "The Moon", kind: "a sailboat"),
        Golden(label: "very long line", lines: [String(repeating: "lantern ", count: 40)],
               lead: "The poem dissolved. This is what it named:", name: "Lantern", kind: "a nail polish"),
        Golden(label: "unicode lines", lines: ["café naïve résumé", "über straße", "日本語 の 詩"],
               lead: "Gone — but not before it became", name: "Straße Café", kind: "a garden rose"),
        Golden(label: "lines the mock stranger can produce",
               lines: ["lanterns drift down the dark stream", "snow settles on the still pine", "frost"],
               lead: "It's gone now — but it left a name behind.", name: "Lanterns Drift", kind: "a racehorse"),
    ]

    /// Separate `#expect`s so a failure prints each actual value.
    @Test(arguments: goldens)
    func golden(_ g: Golden) throws {
        let coined = try #require(PoemNaming.coin(from: g.lines))
        #expect(coined.name == g.name)
        #expect(coined.kind == g.kind)
        #expect(coined.lead == g.lead)
    }

    /// No letter words of 3+ characters means nothing to coin from.
    @Test(arguments: [
        [String](),
        ["", "   ", ""],
        ["🌸🌸🌸", "  ", "✨✨"],
    ])
    func noContentWordsCoinsNothing(_ lines: [String]) {
        #expect(PoemNaming.coin(from: lines) == nil)
    }

    /// The seed is FNV-1a over the lowercased, newline-joined lines and the words
    /// are title-cased, so letter case in the poem cannot change the name.
    @Test func caseDoesNotChangeTheName() throws {
        let titleCase = ["An Old Silent Pond", "A Frog Jumps Into The Pond", "Splash Silence Again"]
        let lower = try #require(PoemNaming.coin(from: Self.classicHaiku))
        let title = try #require(PoemNaming.coin(from: titleCase))
        #expect(title == lower)
    }

    @Test func coinIsDeterministic() {
        #expect(PoemNaming.coin(from: Self.classicHaiku) == PoemNaming.coin(from: Self.classicHaiku))
    }
}
