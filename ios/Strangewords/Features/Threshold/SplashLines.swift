import Foundation

/// Opening lines for the splash. One is chosen at random each time the
/// threshold appears, so the first words change from visit to visit. Kept in the
/// app's voice — quiet and brief, about a poem shared with a stranger and then
/// released. Two short lines each (a `\n` keeps the two-beat rhythm).
enum SplashLines {
    static let all: [String] = [
        "A poem with a stranger.\nThen let it go.",
        "Three lines with someone\nyou'll never meet.",
        "Begin a poem.\nA stranger will finish it.",
        "Write together,\nthen let the words drift away.",
        "Something small and shared,\nthen released.",
        "Meet inside a poem.\nLeave it behind.",
        "A few lines between\ntwo strangers, then gone.",
        "A quiet poem,\nmade once and let go.",
        "Trade three lines\nwith a passing stranger.",
        "Make something brief\nwith someone unknown.",
    ]

    /// A random opening line (never empty — falls back to the first).
    static func random() -> String {
        all.randomElement() ?? all[0]
    }
}
