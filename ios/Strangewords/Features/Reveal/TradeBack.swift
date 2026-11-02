import Foundation

/// Phase 6 D-02 trade back. Every value derives only from the server's
/// `tradeOpen`, `youWantTrade` and `partnerWantsTrade` (plus `partnerIsBot`),
/// never from anything the client infers. Copy is pinned by `TradeBackTests`
/// and the Phase 5 voice rule (`PartnerPresenceTests`, T-05-13).
enum TradeBack {
    enum Offer: Equatable { case none, offer, accept, waiting, passed }

    static func offer(tradeOpen: Bool, youWantTrade: Bool, partnerWantsTrade: Bool) -> Offer {
        .none
    }

    static let buttonLabel = ""

    static func showsButton(_ offer: Offer) -> Bool {
        false
    }

    static func caption(_ offer: Offer, partnerIsBot: Bool) -> String? {
        nil
    }

    static func buttonHint(_ offer: Offer, partnerIsBot: Bool) -> String? {
        nil
    }
}
