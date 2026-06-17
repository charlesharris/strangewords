import SwiftUI

/// The threshold: a single chosen step into the ritual, not an auto-queue
/// (brief.v4.md §5). No queue language, no chrome implying permanence.
struct ThresholdView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Text("Haiku for strangers")
                    .font(Theme.display(34))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                Text("Write three lines with someone you'll never meet.\nThen let it go.")
                    .font(Theme.chrome)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: model.begin) {
                Text("begin")
                    .font(Theme.poem(22))
                    .foregroundStyle(palette.ink)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(palette.secondary.opacity(0.4), lineWidth: 1)
                    )
            }
            .accessibilityHint("Steps into the waiting room to be matched with a stranger.")
            Spacer().frame(height: 40)
        }
    }
}
