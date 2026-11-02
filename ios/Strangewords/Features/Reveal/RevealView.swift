import SwiftUI

/// The completed poem, shown whole and briefly. Tapping "let it go" hands off to
/// the full-screen dissolution (the `.dissolving` phase, rendered by `RootView`
/// using the active theme's effect). The server also caps the reveal window so
/// an untouched poem still dissolves (brief.v4.md §8).
///
/// While the server says the trade is open (Phase 6 D-02), a quiet "trade back"
/// affordance sits above "let it go": the offer is optional, and the default
/// path — doing nothing, or letting go — remains dissolution. Its state and
/// copy come entirely from `TradeBack` over the view's three server fields.
struct RevealView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let session: SessionView
    @State private var appeared = false

    private var tradeOffer: TradeBack.Offer {
        TradeBack.offer(tradeOpen: session.tradeOpen, youWantTrade: session.youWantTrade, partnerWantsTrade: session.partnerWantsTrade)
    }

    var body: some View {
        VStack(spacing: 30) {
            if let caption = PartnerPresence.caption(partnerIsBot: session.partnerIsBot, finished: true) {
                PartnerPresence(caption: caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            Spacer()
            VStack(spacing: 18) {
                ForEach(Array(session.lines.enumerated()), id: \.offset) { _, line in
                    PoemLine(text: line)
                }
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeIn(duration: 1.2), value: appeared)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("The finished poem: " + session.lines.joined(separator: ". "))

            Spacer()
            VStack(spacing: 14) {
                if let caption = TradeBack.caption(tradeOffer, partnerIsBot: session.partnerIsBot) {
                    Text(caption)
                        .font(Theme.label)
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .legibilityBacking(palette)
                }
                if TradeBack.showsButton(tradeOffer) {
                    Button {
                        Haptics.soft()
                        model.tradeBack()
                    } label: {
                        Text(TradeBack.buttonLabel).font(Theme.poem(18))
                    }
                    .buttonStyle(.ritual)
                    .accessibilityHint(TradeBack.buttonHint(tradeOffer, partnerIsBot: session.partnerIsBot) ?? "")
                }
                Button {
                    Haptics.soft()
                    model.release()
                } label: {
                    Text("let it go").font(Theme.poem(18))
                }
                .buttonStyle(.ritual)
                .accessibilityHint("Dismisses the poem. It will not be saved.")
            }
            Spacer().frame(height: 36)
        }
        .onAppear { appeared = true }
        .onChange(of: tradeOffer) { _, offer in
            // The partner asked, or the moment passed: say so, the way ComposeView
            // posts its arrival announcement.
            if offer == .accept || offer == .passed,
               let caption = TradeBack.caption(offer, partnerIsBot: session.partnerIsBot) {
                AccessibilityNotification.Announcement(caption).post()
            }
        }
    }
}
