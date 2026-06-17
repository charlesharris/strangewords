import SwiftUI

/// The shared style for the app's ritual buttons — begin, offer a line, let it
/// go, begin again. A soft frosted capsule that stays legible over any scene,
/// including the dusk-deepened reveal, with a quiet press response. The label
/// supplies its own serif font; the style supplies the readable backing, the
/// hairline border, the disabled dimming, and the press feedback.
struct RitualButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // `onAccent` is light on day palettes and dark at night — the opposite
        // luminance of `ink` — so the capsule reads on any scene, including the
        // dusk-deepened reveal where the bottom of the screen goes dark.
        configuration.label
            .foregroundStyle(palette.ink.opacity(isEnabled ? 1 : 0.45))
            .padding(.vertical, 13)
            .padding(.horizontal, 34)
            .background(palette.onAccent.opacity(isEnabled ? 0.85 : 0.55), in: Capsule())
            .overlay(
                Capsule().stroke(palette.ink.opacity(isEnabled ? 0.22 : 0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RitualButtonStyle {
    /// `.buttonStyle(.ritual)` — the app's standard button chrome.
    static var ritual: RitualButtonStyle { RitualButtonStyle() }
}
