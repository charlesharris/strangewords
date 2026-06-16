import SwiftUI

/// RootView switches on the model's phase over the day/night scene. Transitions
/// are deliberately paced (a gentle fade) to honor the arc anticipation →
/// intimacy → revelation → loss (brief.v4.md §8). The palette is chosen from
/// the local time and provided to every view through the environment.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tod = TimeOfDay.now()

    var body: some View {
        let palette = tod.palette
        ZStack {
            SceneBackground(palette: palette, timeOfDay: tod)
            content
                .padding(.horizontal, 28)
        }
        .environment(\.palette, palette)
        .environment(\.timeOfDay, tod)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.6), value: model.phase)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tod = TimeOfDay.now() }
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
