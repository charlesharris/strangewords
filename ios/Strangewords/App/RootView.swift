import SwiftUI

/// The two ways the day/night scene can be drawn. Swap `RootView.sceneStyle`
/// to change the whole app's backdrop; both stay available as the look evolves.
enum SceneStyle {
    case pixel      // procedural pixel-art scene (PixelScene)
    case painterly  // the soft vector scene (SceneBackground)
}

/// RootView switches on the model's phase over the day/night scene. Transitions
/// are deliberately paced (a gentle fade) to honor the arc anticipation →
/// intimacy → revelation → loss (brief.v4.md §8). The palette is chosen from
/// the local time and provided to every view through the environment.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tod = TimeOfDay.now()
    /// Set once the dev toggle pins a time of day, so returning to foreground
    /// doesn't snap the preview back to the real local hour.
    @State private var todPinned = false

    /// The active backdrop. [TUNABLE] — pixel art is the current look.
    private let sceneStyle: SceneStyle = .pixel

    var body: some View {
        let palette = tod.palette
        ZStack {
            background(palette)
            content
                .padding(.horizontal, 28)
        }
        .overlay(alignment: .topTrailing) { devTimeOfDayToggle(palette) }
        .environment(\.palette, palette)
        .environment(\.timeOfDay, tod)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.6), value: model.phase)
        .animation(.easeInOut(duration: 0.6), value: tod)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !todPinned { tod = TimeOfDay.now() }
        }
    }

    /// A small dev-only chip that cycles the time-of-day backdrop, so the three
    /// scenes can be previewed without waiting for the clock. Hidden in normal
    /// builds (see `Dev.showControls`).
    @ViewBuilder
    private func devTimeOfDayToggle(_ palette: Palette) -> some View {
        if Dev.showControls {
            Button {
                todPinned = true
                tod = tod.next
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: todIcon)
                    Text(tod.rawValue)
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(palette.ink.opacity(0.75))
            }
            .padding(.top, 6)
            .padding(.trailing, 14)
            .accessibilityLabel("Developer: cycle time of day, currently \(tod.rawValue)")
        }
    }

    private var todIcon: String {
        switch tod {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .night:     return "moon.stars.fill"
        }
    }

    @ViewBuilder
    private func background(_ palette: Palette) -> some View {
        switch sceneStyle {
        case .pixel:     PixelScene(palette: palette, timeOfDay: tod)
        case .painterly: SceneBackground(palette: palette, timeOfDay: tod)
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
