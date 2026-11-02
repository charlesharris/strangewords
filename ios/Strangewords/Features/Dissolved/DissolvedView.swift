import SwiftUI

/// The gentle conclusion. Invites return, never apologizes (brief.v4.md §8).
///
/// Every *completed* poem leaves one durable thing behind: a name it coined for
/// itself (see `Naming/PoemNaming.swift`) — one name per completed poem, two
/// after a trade back (Phase 6 D-04). The poems are still gone; these are the
/// keepsakes. An ending with no completed poem (a stranger left, no one came)
/// shows the plain farewell; an interrupted second poem shows its farewell line
/// above poem 1's name.
struct DissolvedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let reason: AppModel.Reason
    @State private var appeared = false

    var body: some View {
        Group {
            if !model.keepsakes.isEmpty {
                keepsakeBody(model.keepsakes)
            } else {
                farewellBody
            }
        }
        .onAppear { appeared = true }
    }

    // MARK: - The keepsakes the poems left behind

    /// What VoiceOver reads for the coined names, one sentence per keepsake.
    static func keepsakeAccessibility(_ keepsakes: [CoinedName]) -> String {
        keepsakes.map { "\($0.lead) \($0.name)." }.joined(separator: " ")
    }

    private func keepsakeBody(_ keepsakes: [CoinedName]) -> some View {
        VStack(spacing: 32) {
            Spacer()
            // A partner left, or you stepped away, during poem 2 after a trade:
            // say so first, then still show what completed.
            if reason != .completedAndGone {
                Text(message)
                    .font(Theme.poem(22))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .skyTextBacking(palette)
            }
            VStack(spacing: 28) {
                ForEach(Array(keepsakes.enumerated()), id: \.offset) { _, keepsake in
                    VStack(spacing: 16) {
                        Text(keepsake.lead)
                            .font(Theme.chrome)
                            .foregroundStyle(palette.secondary)
                        Text(keepsake.name)
                            .font(Theme.display(34))
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .skyTextBacking(palette)
            .opacity(appeared ? 1 : 0)
            .animation(.easeIn(duration: 1.2), value: appeared)

            Spacer()
            beginAgainButton
            Spacer().frame(height: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reason == .completedAndGone
            ? Self.keepsakeAccessibility(keepsakes)
            : message + " " + Self.keepsakeAccessibility(keepsakes))
    }

    // MARK: - The plain farewell

    private var farewellBody: some View {
        VStack(spacing: 32) {
            Spacer()
            Text(message)
                .font(Theme.poem(22))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .skyTextBacking(palette)
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
