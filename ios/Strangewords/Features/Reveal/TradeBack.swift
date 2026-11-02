import Foundation

/// Phase 6 D-02 trade back. Every value derives only from the server's
/// `tradeOpen`, `youWantTrade` and `partnerWantsTrade` (plus `partnerIsBot`),
/// never from anything the client infers. Copy is pinned by `TradeBackTests`
/// and the Phase 5 voice rule (`PartnerPresenceTests`, T-05-13): robot-poet
/// strings name the robot poet and never call it a stranger or someone; human
/// strings never mention the robot.
enum TradeBack {
    /// The reveal's trade state, derived from the server view alone.
    enum Offer: Equatable { case none, offer, accept, waiting, passed }

    /// The pure mapping over the three server fields (T-06-16):
    /// - you asked and the trade is still open → `.waiting`
    /// - you asked and the trade has closed → `.passed`
    /// - the partner asked and you have not → `.accept`
    /// - the trade is open and nobody asked → `.offer`
    /// - everything else (no open trade, nothing asked) → `.none`
    static func offer(tradeOpen: Bool, youWantTrade: Bool, partnerWantsTrade: Bool) -> Offer {
        if youWantTrade { return tradeOpen ? .waiting : .passed }
        if tradeOpen { return partnerWantsTrade ? .accept : .offer }
        return .none
    }

    static let buttonLabel = "trade back"

    /// The button exists only while there is something to ask or answer.
    static func showsButton(_ offer: Offer) -> Bool {
        offer == .offer || offer == .accept
    }

    /// The quiet caption above the buttons; nil when there is nothing to say
    /// (`.none` renders today's reveal, `.offer` lets the button speak alone).
    static func caption(_ offer: Offer, partnerIsBot: Bool) -> String? {
        switch offer {
        case .none, .offer:
            return nil
        case .accept:
            return partnerIsBot ? "the robot poet would like to trade back"
                                : "the stranger would like to trade back"
        case .waiting:
            return partnerIsBot ? "the robot poet is thinking it over"
                                : "waiting to see if the stranger trades back"
        case .passed:
            return partnerIsBot ? "no trade back with the robot poet this time"
                                : "no trade back this time"
        }
    }

    /// The VoiceOver hint on the trade button, sentence case like RevealView's.
    static func buttonHint(_ offer: Offer, partnerIsBot: Bool) -> String? {
        switch offer {
        case .offer:
            return partnerIsBot ? "Offers the robot poet a second poem, the other way around."
                                : "Offers the stranger a second poem, the other way around."
        case .accept:
            return partnerIsBot ? "Accepts the robot poet's offer. A second poem begins, the other way around."
                                : "Accepts the stranger's offer. A second poem begins, the other way around."
        case .none, .waiting, .passed:
            return nil
        }
    }
}
