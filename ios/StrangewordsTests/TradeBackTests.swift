import Testing
import Foundation
@testable import Strangewords

/// Pins the Reveal trade-back state mapping and every trade string (Phase 6
/// D-02, T-06-15, T-06-16). The mapping is a pure function of the server's
/// three trade fields, covered over all eight combinations; the copy is pinned
/// exactly, lowercase in the visible voice, and obeys the Phase 5 voice rule
/// (the robot-poet strings also join `PartnerPresenceTests.robotStrings`).
struct TradeBackTests {
    // MARK: - State mapping

    /// All 8 combinations of (tradeOpen, youWantTrade, partnerWantsTrade).
    @Test func offerStateMapping() {
        // youWantTrade with tradeOpen → .waiting
        #expect(TradeBack.offer(tradeOpen: true, youWantTrade: true, partnerWantsTrade: false) == .waiting)
        #expect(TradeBack.offer(tradeOpen: true, youWantTrade: true, partnerWantsTrade: true) == .waiting)
        // youWantTrade without tradeOpen → .passed
        #expect(TradeBack.offer(tradeOpen: false, youWantTrade: true, partnerWantsTrade: false) == .passed)
        #expect(TradeBack.offer(tradeOpen: false, youWantTrade: true, partnerWantsTrade: true) == .passed)
        // tradeOpen and partnerWantsTrade without youWantTrade → .accept
        #expect(TradeBack.offer(tradeOpen: true, youWantTrade: false, partnerWantsTrade: true) == .accept)
        // tradeOpen alone → .offer
        #expect(TradeBack.offer(tradeOpen: true, youWantTrade: false, partnerWantsTrade: false) == .offer)
        // everything else → .none
        #expect(TradeBack.offer(tradeOpen: false, youWantTrade: false, partnerWantsTrade: false) == TradeBack.Offer.none)
        #expect(TradeBack.offer(tradeOpen: false, youWantTrade: false, partnerWantsTrade: true) == TradeBack.Offer.none)
    }

    @Test func buttonOnlyForOfferAndAccept() {
        #expect(TradeBack.showsButton(.offer))
        #expect(TradeBack.showsButton(.accept))
        #expect(!TradeBack.showsButton(.none))
        #expect(!TradeBack.showsButton(.waiting))
        #expect(!TradeBack.showsButton(.passed))
    }

    // MARK: - Copy, pinned exactly

    @Test func humanCopyIsPinned() {
        #expect(TradeBack.buttonLabel == "trade back")

        #expect(TradeBack.caption(.none, partnerIsBot: false) == nil)
        #expect(TradeBack.caption(.offer, partnerIsBot: false) == nil)
        #expect(TradeBack.caption(.accept, partnerIsBot: false) == "the stranger would like to trade back")
        #expect(TradeBack.caption(.waiting, partnerIsBot: false) == "waiting to see if the stranger trades back")
        #expect(TradeBack.caption(.passed, partnerIsBot: false) == "no trade back this time")

        #expect(TradeBack.buttonHint(.none, partnerIsBot: false) == nil)
        #expect(TradeBack.buttonHint(.waiting, partnerIsBot: false) == nil)
        #expect(TradeBack.buttonHint(.passed, partnerIsBot: false) == nil)
        #expect(TradeBack.buttonHint(.offer, partnerIsBot: false)
            == "Offers the stranger a second poem, the other way around.")
        #expect(TradeBack.buttonHint(.accept, partnerIsBot: false)
            == "Accepts the stranger's offer. A second poem begins, the other way around.")
    }

    @Test func robotPoetCopyIsPinned() {
        #expect(TradeBack.caption(.none, partnerIsBot: true) == nil)
        #expect(TradeBack.caption(.offer, partnerIsBot: true) == nil)
        #expect(TradeBack.caption(.accept, partnerIsBot: true) == "the robot poet would like to trade back")
        #expect(TradeBack.caption(.waiting, partnerIsBot: true) == "the robot poet is thinking it over")
        #expect(TradeBack.caption(.passed, partnerIsBot: true) == "no trade back with the robot poet this time")

        #expect(TradeBack.buttonHint(.none, partnerIsBot: true) == nil)
        #expect(TradeBack.buttonHint(.waiting, partnerIsBot: true) == nil)
        #expect(TradeBack.buttonHint(.passed, partnerIsBot: true) == nil)
        #expect(TradeBack.buttonHint(.offer, partnerIsBot: true)
            == "Offers the robot poet a second poem, the other way around.")
        #expect(TradeBack.buttonHint(.accept, partnerIsBot: true)
            == "Accepts the robot poet's offer. A second poem begins, the other way around.")
    }

    // MARK: - Voice

    private static let states: [TradeBack.Offer] = [.none, .offer, .accept, .waiting, .passed]

    /// Every non-nil caption, both partners, plus the button label.
    private var visibleCopy: [String] {
        [TradeBack.buttonLabel]
            + Self.states.compactMap { TradeBack.caption($0, partnerIsBot: false) }
            + Self.states.compactMap { TradeBack.caption($0, partnerIsBot: true) }
    }

    /// Every trade string: visible copy plus the VoiceOver hints.
    private var allCopy: [String] {
        visibleCopy
            + Self.states.compactMap { TradeBack.buttonHint($0, partnerIsBot: false) }
            + Self.states.compactMap { TradeBack.buttonHint($0, partnerIsBot: true) }
    }

    private func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    /// The app's chrome voice is lowercase; the VoiceOver hints are sentence case,
    /// like RevealView's, and are excluded.
    @Test func visibleCopyIsLowercase() {
        for s in visibleCopy {
            #expect(s == s.lowercased(), "not lowercase: \(s)")
        }
    }

    /// The StepAwayTests banned set (the ritual voice).
    @Test func copyKeepsTheRitualVoice() {
        let banned: Set<String> = ["bot", "ai", "assistant", "chatbot", "algorithm", "queue",
                                   "searching", "matched", "session", "quit", "exit", "cancel", "leave"]
        for s in allCopy {
            #expect(words(s).isDisjoint(with: banned), "cold word in: \(s)")
        }
    }

    /// Human-partner strings never mention the robot (T-05-13's complement).
    @Test func humanCopyNeverNamesTheRobotPoet() {
        let human = Self.states.compactMap { TradeBack.caption($0, partnerIsBot: false) }
            + Self.states.compactMap { TradeBack.buttonHint($0, partnerIsBot: false) }
            + [TradeBack.buttonLabel]
        for s in human {
            #expect(!words(s).contains("robot"), "names the robot in human copy: \(s)")
        }
    }
}
