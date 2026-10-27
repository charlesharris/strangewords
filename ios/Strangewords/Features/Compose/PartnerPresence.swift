import SwiftUI

/// The named-presence chip: says, quietly and for the whole session, that the
/// partner is the robot poet.
///
/// This is a persistent disclosure contract (Phase 5, D-04). It renders only
/// from the server's `partnerIsBot` (or `LocalBackend`'s mirror of it), never
/// from anything the client infers or caches, and it must never be softened,
/// removed or restyled away by a later theme or copy pass. Every string the
/// robot poet appears in lives here as a pure function so tests can pin it.
struct PartnerPresence: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let caption: String

    var body: some View {
        Text(caption)
            .font(Theme.label)
            .foregroundStyle(palette.ink)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(backing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityText)
    }

    /// A capsule normally; a rounded block once the text can run past two lines.
    @ViewBuilder
    private var backing: some View {
        if dynamicTypeSize.isAccessibilitySize {
            RoundedRectangle(cornerRadius: 16).fill(palette.onAccent.opacity(0.6))
        } else {
            Capsule().fill(palette.onAccent.opacity(0.6))
        }
    }

    // MARK: - Copy (pure, unit-tested)

    /// The chip text, or nil when the partner is a human (no chip in the hierarchy).
    static func caption(partnerIsBot: Bool, finished: Bool) -> String? {
        guard partnerIsBot else { return nil }
        return finished ? "written with the robot poet" : "writing with the robot poet"
    }

    /// The their-turn lines in Compose. The human copy is unchanged from 0.1.0;
    /// the robot poet's copy makes no push promise because none is sent for it.
    struct TheirTurnCopy: Equatable {
        let primary: String
        let secondary: String
        let accessibility: String
    }

    static func theirTurn(partnerIsBot: Bool) -> TheirTurnCopy {
        if partnerIsBot {
            return TheirTurnCopy(
                primary: "the robot poet is with the poem now",
                secondary: "its line will be here in a moment",
                accessibility: "Waiting for the robot poet to write its line."
            )
        }
        return TheirTurnCopy(
            primary: "the stranger is with the poem now",
            secondary: "it's fine to put this down — you'll be told when there's a line for you",
            accessibility: "Waiting for the stranger to write their line."
        )
    }

    /// The soft second line in the waiting room: only for an opted-in user, and
    /// never during "stepping in…".
    static func waitingLine(allowBot: Bool, connecting: Bool) -> String? {
        guard allowBot, !connecting else { return nil }
        return "if no one comes, the robot poet may keep you company"
    }

    static func waitingAccessibility(allowBot: Bool, connecting: Bool) -> String {
        if connecting { return "Connecting" }
        return allowBot
            ? "Waiting for a stranger to arrive. If no one comes, the robot poet may keep you company."
            : "Waiting for a stranger to arrive"
    }

    /// What VoiceOver reads for the chip: adds the fact the visible text leaves implicit.
    static let accessibilityText = "Your partner is the robot poet, software on our server, not a person."

    /// Posted once when a robot-poet session's Compose first appears.
    static let arrivalAnnouncement = "You're now writing with the robot poet."
}
