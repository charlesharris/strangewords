import SwiftUI

/// The completed poem, shown whole and briefly. Tapping "let it go" hands off to
/// the full-screen dissolution (the `.dissolving` phase, rendered by `RootView`
/// using the active theme's effect). The server also caps the reveal window so
/// an untouched poem still dissolves (brief.v4.md §8).
struct RevealView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
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
            Button {
                Haptics.soft()
                model.release()
            } label: {
                Text("let it go").font(Theme.poem(18))
            }
            .buttonStyle(.ritual)
            .accessibilityHint("Dismisses the poem. It will not be saved.")
            Spacer().frame(height: 36)
        }
        .onAppear { appeared = true }
    }
}
