import SwiftUI

/// The completed poem, shown whole and briefly. Dismissing it lets it go; the
/// server also caps the reveal window so it dissolves even if untouched
/// (brief.v4.md §8). The dissolution animation deepens in Phase 4.
struct RevealView: View {
    @Environment(AppModel.self) private var model
    let session: SessionView
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 30) {
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
            Button("let it go") { model.dismissReveal() }
                .font(Theme.poem(18))
                .foregroundStyle(Theme.whisper)
                .accessibilityHint("Dismisses the poem. It will not be saved.")
            Spacer().frame(height: 36)
        }
        .onAppear { appeared = true }
    }
}
