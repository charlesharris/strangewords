import SwiftUI

/// The threshold: a single chosen step into the ritual, not an auto-queue
/// (brief.v4.md §5). No queue language, no chrome implying permanence.
struct ThresholdView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    /// A fresh opening line each time the threshold appears.
    @State private var tagline = SplashLines.random()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Text("Stranger Words")
                    .font(Theme.display(34))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                Text(tagline)
                    .font(Theme.chrome)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: model.begin) {
                Text("begin").font(Theme.poem(22))
            }
            .buttonStyle(.ritual)
            .accessibilityHint("Steps into the waiting room to be matched with a stranger.")
            Spacer().frame(height: 40)
        }
    }
}
