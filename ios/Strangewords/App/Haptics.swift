import UIKit

/// Small, sparing haptics for the few moments that carry weight — the app is
/// quiet, so touch is too. Centralized so the tactile vocabulary stays
/// consistent: a soft tap for a deliberate act, a gentle rigid tap when
/// something arrives, a success note when the poem is whole.
@MainActor
enum Haptics {
    /// A deliberate act: crossing the threshold, letting the poem go.
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Offering a line — a light, brief touch.
    static func offer() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }

    /// Something arrived: a stranger matched, or the turn has come back to you.
    static func arrival() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
    }

    /// The poem is complete and revealed.
    static func reveal() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
