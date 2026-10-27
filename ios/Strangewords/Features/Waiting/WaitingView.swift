import SwiftUI

/// The anteroom. Not a loading screen — "being alone in a quiet room where
/// someone else might arrive" (brief.v4.md §8). A slow breathing dot stands in
/// for richer ambient motion to come in Phase 4.
struct WaitingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let connecting: Bool
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 36) {
            Spacer()
            Circle()
                .fill(palette.accent.opacity(0.6))
                .frame(width: 12, height: 12)
                .scaleEffect(breathe ? 1.6 : 0.8)
                .opacity(breathe ? 0.3 : 0.7)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(connecting ? "stepping in…" : "no one else is here just yet")
                    .font(Theme.chrome)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                if let line = PartnerPresence.waitingLine(allowBot: model.allowBot, connecting: connecting) {
                    Text(line)
                        .font(Theme.label)
                        .foregroundStyle(palette.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()

            if !connecting {
                Button("step back out") { model.leave() }
                    .font(Theme.label)
                    .foregroundStyle(palette.secondary)
                Spacer().frame(height: 24)
            }
        }
        .onAppear { breathe = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(PartnerPresence.waitingAccessibility(allowBot: model.allowBot, connecting: connecting))
    }
}
