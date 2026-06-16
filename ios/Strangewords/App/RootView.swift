import SwiftUI

/// RootView switches on the model's phase. Transitions are deliberately paced
/// (a gentle fade) to honor the arc anticipation → intimacy → revelation →
/// loss (brief.v4.md §8). Reveal/dissolution motion deepens in Phase 4.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            content
                .padding(.horizontal, 28)
        }
        .animation(.easeInOut(duration: 0.6), value: model.phase)
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
