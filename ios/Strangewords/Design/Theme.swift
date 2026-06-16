import SwiftUI

/// Restraint over decoration: typography is the primary material, generous
/// space, quiet color (brief.v4.md §8).
enum Theme {
    static let ink = Color.primary
    static let whisper = Color.secondary
    static let paper = Color(.systemBackground)

    /// The poem itself — a serif voice, set large and calm.
    static func poem(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// Quiet chrome — sans, small, receding.
    static let chrome = Font.system(size: 15, weight: .regular, design: .default)
    static let label = Font.system(size: 13, weight: .regular, design: .default)
}

/// A line of poem rendered in the shared serif voice.
struct PoemLine: View {
    let text: String
    var dim: Bool = false
    var body: some View {
        Text(text)
            .font(Theme.poem())
            .foregroundStyle(dim ? Theme.whisper : Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}
