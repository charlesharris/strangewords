import SwiftUI

/// The gentle conclusion. Invites return, never apologizes (brief.v4.md §8).
struct DissolvedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let reason: AppModel.Reason

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text(message)
                .font(Theme.poem(22))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: model.reset) {
                Text("begin again").font(Theme.poem(20))
            }
            .buttonStyle(.ritual)
            Spacer().frame(height: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var message: String {
        switch reason {
        case .completedAndGone: return "It's gone now.\nSomething happened, and then it wasn't."
        case .partnerLeft:      return "The stranger slipped away.\nThe poem went with them."
        case .noOneCame:        return "No one came this time.\nThe room is still here when you'd like to try again."
        case .ended:            return "That's the end of it."
        }
    }
}
