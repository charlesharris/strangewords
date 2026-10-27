import SwiftUI

/// RED-phase compile scaffolding: the API shape with no behavior yet.
struct PartnerPresence: View {
    let caption: String

    struct TheirTurnCopy: Equatable {
        let primary: String
        let secondary: String
        let accessibility: String
    }

    static func caption(partnerIsBot: Bool, finished: Bool) -> String? { "" }
    static func theirTurn(partnerIsBot: Bool) -> TheirTurnCopy {
        TheirTurnCopy(primary: "", secondary: "", accessibility: "")
    }
    static func waitingLine(allowBot: Bool, connecting: Bool) -> String? { "" }
    static func waitingAccessibility(allowBot: Bool, connecting: Bool) -> String { "" }
    static let accessibilityText = ""
    static let arrivalAnnouncement = ""

    var body: some View { Text(caption) }
}
