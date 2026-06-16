import SwiftUI

/// The anteroom. Not a loading screen — "being alone in a quiet room where
/// someone else might arrive" (brief.v4.md §8). A slow breathing dot stands in
/// for richer ambient motion to come in Phase 4.
struct WaitingView: View {
    @Environment(AppModel.self) private var model
    let connecting: Bool
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 36) {
            Spacer()
            Circle()
                .fill(Theme.whisper.opacity(0.5))
                .frame(width: 12, height: 12)
                .scaleEffect(breathe ? 1.6 : 0.8)
                .opacity(breathe ? 0.3 : 0.7)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
                .accessibilityHidden(true)

            Text(connecting ? "stepping in…" : "no one else is here just yet")
                .font(Theme.chrome)
                .foregroundStyle(Theme.whisper)
                .multilineTextAlignment(.center)
            Spacer()

            if !connecting {
                Button("step back out") { model.leave() }
                    .font(Theme.label)
                    .foregroundStyle(Theme.whisper)
                Spacer().frame(height: 24)
            }
        }
        .onAppear { breathe = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connecting ? "Connecting" : "Waiting for a stranger to arrive")
    }
}
