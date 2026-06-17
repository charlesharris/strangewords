import SwiftUI

/// The gentle conclusion. Invites return, never apologizes (brief.v4.md §8).
///
/// When a poem actually *completed*, the dissolution leaves one durable thing
/// behind: a name it coined for some random small thing — a beer, a mustard, a
/// racehorse (see `Naming/PoemNaming.swift`). The poem is still gone; this is the
/// keepsake. Every other ending (a stranger left, no one came) shows the plain
/// farewell.
struct DissolvedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let reason: AppModel.Reason
    @State private var appeared = false

    var body: some View {
        Group {
            if reason == .completedAndGone, let keepsake = model.keepsake {
                keepsakeBody(keepsake)
            } else {
                farewellBody
            }
        }
        .onAppear { appeared = true }
    }

    // MARK: - The keepsake the poem left behind

    private func keepsakeBody(_ keepsake: CoinedName) -> some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 16) {
                Text(keepsake.lead)
                    .font(Theme.chrome)
                    .foregroundStyle(palette.secondary)
                Text(keepsake.name)
                    .font(Theme.display(34))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(keepsake.kind)
                    .font(Theme.poemItalic(17))
                    .foregroundStyle(palette.secondary)
            }
            .multilineTextAlignment(.center)
            .opacity(appeared ? 1 : 0)
            .animation(.easeIn(duration: 1.2), value: appeared)

            Spacer()
            beginAgainButton
            Spacer().frame(height: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(keepsake.lead) \(keepsake.name), \(keepsake.kind).")
    }

    // MARK: - The plain farewell

    private var farewellBody: some View {
        VStack(spacing: 32) {
            Spacer()
            Text(message)
                .font(Theme.poem(22))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
            Spacer()
            beginAgainButton
            Spacer().frame(height: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var beginAgainButton: some View {
        Button(action: model.reset) {
            Text("begin again").font(Theme.poem(20))
        }
        .buttonStyle(.ritual)
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
