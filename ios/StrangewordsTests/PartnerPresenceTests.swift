import Testing
import Foundation
@testable import Strangewords

/// Pins every disclosure string of the robot poet (Phase 5, D-04, T-05-13,
/// T-05-16). The chip and the their-turn copy are pure functions of the server's
/// `partnerIsBot`; nothing here computes or infers it.
struct PartnerPresenceTests {
    // MARK: - Caption (the persistent named-presence chip)

    @Test func humanPartnerHasNoCaption() {
        #expect(PartnerPresence.caption(partnerIsBot: false, finished: false) == nil)
        #expect(PartnerPresence.caption(partnerIsBot: false, finished: true) == nil)
    }

    @Test func robotPoetCaptionWhileWriting() {
        #expect(PartnerPresence.caption(partnerIsBot: true, finished: false) == "writing with the robot poet")
    }

    @Test func robotPoetCaptionOnceFinished() {
        #expect(PartnerPresence.caption(partnerIsBot: true, finished: true) == "written with the robot poet")
    }

    // MARK: - Their-turn copy

    @Test func humanTheirTurnCopyIsUnchanged() {
        #expect(PartnerPresence.theirTurn(partnerIsBot: false) == PartnerPresence.TheirTurnCopy(
            primary: "the stranger is with the poem now",
            secondary: "it's fine to put this down — you'll be told when there's a line for you",
            accessibility: "Waiting for the stranger to write their line."
        ))
    }

    @Test func robotPoetTheirTurnCopyPromisesNoPush() {
        #expect(PartnerPresence.theirTurn(partnerIsBot: true) == PartnerPresence.TheirTurnCopy(
            primary: "the robot poet is with the poem now",
            secondary: "its line will be here in a moment",
            accessibility: "Waiting for the robot poet to write its line."
        ))
    }

    // MARK: - Waiting room soft line

    @Test func waitingLineOnlyWhenOptedInAndNotConnecting() {
        #expect(PartnerPresence.waitingLine(allowBot: true, connecting: false)
            == "if no one comes, the robot poet may keep you company")
        #expect(PartnerPresence.waitingLine(allowBot: false, connecting: false) == nil)
        #expect(PartnerPresence.waitingLine(allowBot: true, connecting: true) == nil)
        #expect(PartnerPresence.waitingLine(allowBot: false, connecting: true) == nil)
    }

    @Test func waitingAccessibilityDefaultIsUnchanged() {
        #expect(PartnerPresence.waitingAccessibility(allowBot: false, connecting: false)
            == "Waiting for a stranger to arrive")
    }

    @Test func waitingAccessibilityMentionsTheRobotPoetWhenOptedIn() {
        #expect(PartnerPresence.waitingAccessibility(allowBot: true, connecting: false)
            == "Waiting for a stranger to arrive. If no one comes, the robot poet may keep you company.")
    }

    @Test func connectingAccessibilityIgnoresTheOptIn() {
        #expect(PartnerPresence.waitingAccessibility(allowBot: false, connecting: true) == "Connecting")
        #expect(PartnerPresence.waitingAccessibility(allowBot: true, connecting: true) == "Connecting")
    }

    // MARK: - VoiceOver strings

    @Test func chipAccessibilityStatesItIsSoftware() {
        #expect(PartnerPresence.accessibilityText
            == "Your partner is the robot poet, software on our server, not a person.")
    }

    @Test func arrivalAnnouncementNamesTheRobotPoet() {
        #expect(PartnerPresence.arrivalAnnouncement == "You're now writing with the robot poet.")
    }

    // MARK: - Settings copy

    @Test func settingsCopyIsPinned() {
        #expect(SettingsView.title == "settings")
        #expect(SettingsView.toggleTitle == "write with the robot poet")
        #expect(SettingsView.helperText == "if no one else arrives after a little while, a robot poet — software on our server, not a person — can write with you, and you'll always be told.")
        #expect(SettingsView.helperText.contains("software"))
        #expect(SettingsView.helperText.contains("not a person"))
    }

    // MARK: - Voice rule (T-05-13)

    /// Every robot-poet string in the UI. The settings title is the one string
    /// that does not name the robot poet.
    private var robotStrings: [String] {
        let turn = PartnerPresence.theirTurn(partnerIsBot: true)
        return [
            PartnerPresence.caption(partnerIsBot: true, finished: false),
            PartnerPresence.caption(partnerIsBot: true, finished: true),
            turn.primary, turn.secondary, turn.accessibility,
            PartnerPresence.waitingLine(allowBot: true, connecting: false),
            PartnerPresence.waitingAccessibility(allowBot: true, connecting: false),
            PartnerPresence.accessibilityText,
            PartnerPresence.arrivalAnnouncement,
            SettingsView.toggleTitle,
            SettingsView.helperText,
        ].compactMap { $0 }
    }

    private func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    @Test func voiceRuleBansColdVocabulary() {
        let banned: Set<String> = ["bot", "ai", "assistant", "chatbot", "algorithm", "queue", "searching", "matched"]
        for s in robotStrings {
            #expect(words(s).isDisjoint(with: banned), "banned word in: \(s)")
        }
    }

    /// The their-turn secondary line is the one continuation line: UI-SPEC pins it
    /// as "its line will be here in a moment", and the primary line above it names
    /// the robot poet, so it is checked against the primary instead.
    @Test func everyRobotStringNamesTheRobotPoet() {
        let continuation = PartnerPresence.theirTurn(partnerIsBot: true).secondary
        #expect(PartnerPresence.theirTurn(partnerIsBot: true).primary.contains("robot poet"))
        for s in robotStrings where s != continuation {
            #expect(s.lowercased().contains("robot poet"), "does not name the robot poet: \(s)")
        }
    }

    @Test func botPartnerCopyNeverCallsItAStrangerOrSomeone() {
        let turn = PartnerPresence.theirTurn(partnerIsBot: true)
        let botCopy = [
            PartnerPresence.caption(partnerIsBot: true, finished: false),
            PartnerPresence.caption(partnerIsBot: true, finished: true),
            turn.primary, turn.secondary, turn.accessibility,
            PartnerPresence.accessibilityText,
            PartnerPresence.arrivalAnnouncement,
        ].compactMap { $0 }
        for s in botCopy {
            let w = words(s)
            #expect(!w.contains("stranger") && !w.contains("someone"), "personifies the robot poet: \(s)")
        }
    }
}
