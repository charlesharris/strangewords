import SwiftUI

/// RootView switches on the model's phase over the active theme's scene.
/// Transitions are deliberately paced (a gentle fade) to honor the arc
/// anticipation → intimacy → revelation → loss (brief.v4.md §8). The theme
/// supplies the palette (chosen from the local time), the background, and the
/// dissolution; all are provided to the rest of the app through the environment.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tod = TimeOfDay.now()
    /// Set once the dev toggle pins a time of day, so returning to foreground
    /// doesn't snap the preview back to the real local hour.
    @State private var todPinned = false
    /// The active theme — defaults to `SW_FORCE_THEME` (if set) or the registry
    /// default; the dev toggle cycles it.
    @State private var theme: any SceneTheme =
        Themes.with(id: ProcessInfo.processInfo.environment["SW_FORCE_THEME"])

    var body: some View {
        let palette = theme.palette(tod)
        ZStack {
            theme.background(tod, palette)
            if Dev.previewDissolution {
                SceneDepthOverlay(palette: palette).opacity(0.7)
                DissolutionPreviewView().padding(.horizontal, 28)
            } else {
                SceneDepthOverlay(palette: palette)
                    .opacity(sceneDepth)
                content
                    .padding(.horizontal, 28)
            }
        }
        .overlay(alignment: .topTrailing) { devControls(palette) }
        .environment(\.palette, palette)
        .environment(\.timeOfDay, tod)
        .environment(\.sceneTheme, theme)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.6), value: model.phase)
        .animation(.easeInOut(duration: 0.6), value: tod)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !todPinned { tod = TimeOfDay.now() }
        }
    }

    /// Dev-only chips (top-trailing): cycle the time of day and the theme, so the
    /// scenes can be previewed without waiting for the clock or rebuilding.
    /// Hidden in normal builds (see `Dev.showControls`).
    @ViewBuilder
    private func devControls(_ palette: Palette) -> some View {
        if Dev.showControls {
            VStack(alignment: .trailing, spacing: 6) {
                devChip(icon: todIcon, label: tod.rawValue, palette: palette) {
                    todPinned = true
                    tod = tod.next
                }
                devChip(icon: "paintpalette.fill", label: theme.name, palette: palette) {
                    theme = Themes.after(theme)
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 14)
        }
    }

    private func devChip(icon: String, label: String, palette: Palette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(palette.ink.opacity(0.75))
        }
        .accessibilityLabel("Developer: \(label)")
    }

    private var todIcon: String {
        switch tod {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .night:     return "moon.stars.fill"
        }
    }

    /// How far the scene has "deepened toward dusk" for the current phase — the
    /// world dims and closes in as the arc moves anticipation → intimacy →
    /// revelation → loss (brief.v4.md §8). Animated via the phase transition.
    private var sceneDepth: Double {
        switch model.phase {
        case .threshold, .connecting, .waiting: return 0
        case .composing:                        return 0.22
        case .reveal:                           return 0.70
        case .dissolved:                        return 1.0
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .threshold:
            ThresholdView().transition(.opacity)
        case .connecting:
            WaitingView(connecting: true).transition(.opacity)
        case .waiting:
            WaitingView(connecting: false).transition(.opacity)
        case .composing(let s):
            ComposeView(session: s).transition(.opacity)
        case .reveal(let s):
            RevealView(session: s).transition(.opacity)
        case .dissolved(let reason):
            DissolvedView(reason: reason).transition(.opacity)
        }
    }
}

/// Dev-only: loops the active dissolution effect over the scene so the petal
/// animation can be seen and tuned without playing a whole poem. Shown when
/// `SW_DEV_DISSOLVE=1` (see `Dev.previewDissolution`).
struct DissolutionPreviewView: View {
    @Environment(\.palette) private var palette
    @Environment(\.timeOfDay) private var timeOfDay
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runID = 0
    private let lines = ["an old silent pond", "a frog slips into the dark", "the moon lets go"]

    var body: some View {
        theme.dissolution.makeBody(
            DissolutionContext(lines: lines, palette: palette, timeOfDay: timeOfDay, reduceMotion: reduceMotion)
        ) {
            runID += 1   // re-create the effect so it plays again, on a loop
        }
        .id(runID)
    }
}

/// A dusk that closes in from the edges as the experience deepens. Drawn at full
/// strength here and modulated by `.opacity(sceneDepth)` upstream, so the
/// transition animates smoothly. It darkens the frame and the ground while
/// leaving the center clear, so the centered poem stays legible even at full
/// depth. The dusk tone follows the time of day (warm plum by day, deep indigo
/// at night).
struct SceneDepthOverlay: View {
    let palette: Palette

    var body: some View {
        GeometryReader { geo in
            let dusk = palette.isDark ? Color(0x070914) : Color(0x4E2433)
            let maxR = max(geo.size.width, geo.size.height)
            ZStack {
                // Dusk gathering at the edges (clear core, dark corners).
                RadialGradient(colors: [.clear, .clear, dusk],
                               center: .center,
                               startRadius: maxR * 0.18,
                               endRadius: maxR * 0.72)
                // The ground falls into deeper shadow.
                LinearGradient(colors: [.clear, dusk.opacity(0.5)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
