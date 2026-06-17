import SwiftUI

/// The completed poem, shown whole and briefly. Tapping "let it go" plays the
/// active dissolution effect (see `Dissolutions.current`) on the poem itself;
/// when the words are gone the session is dismissed and the scene moves on. The
/// server also caps the reveal window so an untouched poem still dissolves
/// (brief.v4.md §8).
struct RevealView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.timeOfDay) private var timeOfDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: SessionView
    @State private var appeared = false
    @State private var releasing = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            if releasing {
                Dissolutions.current.makeBody(dissolutionContext) {
                    model.dismissReveal()
                }
            } else {
                poem
            }

            Spacer()

            // The release control fades out as the poem begins to let go.
            Button("let it go") {
                Haptics.soft()
                withAnimation(.easeInOut(duration: 0.5)) { releasing = true }
            }
            .font(Theme.poem(18))
            .foregroundStyle(palette.secondary)
            .opacity(releasing ? 0 : 1)
            .disabled(releasing)
            .accessibilityHint("Dismisses the poem. It will not be saved.")

            Spacer().frame(height: 36)
        }
        .onAppear { appeared = true }
    }

    private var poem: some View {
        VStack(spacing: 18) {
            ForEach(Array(session.lines.enumerated()), id: \.offset) { _, line in
                PoemLine(text: line)
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeIn(duration: 1.2), value: appeared)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The finished poem: " + session.lines.joined(separator: ". "))
    }

    private var dissolutionContext: DissolutionContext {
        DissolutionContext(
            lines: session.lines,
            palette: palette,
            timeOfDay: timeOfDay,
            reduceMotion: reduceMotion
        )
    }
}
