import SwiftUI

/// The shared legibility backing: a quiet frosted pill of `onAccent` behind copy that
/// would otherwise sit straight on the scene. It is the same recipe the robot-poet chip
/// (`PartnerPresence`) and the settings cards already use, so it reads as part of the
/// app's existing chrome rather than a new element.
///
/// It is used sparingly. The lower screen (draft, hint, error, their-turn copy, exits)
/// is backed in every palette. Sky copy is backed only where `Palette.backsSkyText` is
/// true, the palettes ContrastTests proves no text color can reach 4.5:1 in.
enum Legibility {
    /// Opacity of the onAccent backing. [TUNABLE] Matches the chip and settings cards.
    static let backingOpacity: Double = 0.6
}

extension View {
    /// Always draws the legibility backing. Padding is part of the pill, so it hugs the text.
    func legibilityBacking(_ palette: Palette) -> some View {
        self
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.onAccent.opacity(Legibility.backingOpacity))
            )
    }

    /// Draws the legibility backing only where this palette needs it for sky copy;
    /// otherwise returns the view unchanged (no padding).
    @ViewBuilder
    func skyTextBacking(_ palette: Palette) -> some View {
        if palette.backsSkyText {
            legibilityBacking(palette)
        } else {
            self
        }
    }
}
