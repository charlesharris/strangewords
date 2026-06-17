import SwiftUI

/// The shared poem in progress. Each participant sees the lines so far, then
/// either writes (their turn) or waits in a held-breath state (brief.v4.md §5).
struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let session: SessionView
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 28) {
            Spacer(minLength: 24)

            // Lines written so far, accumulating visibly.
            VStack(spacing: 14) {
                ForEach(Array(session.lines.enumerated()), id: \.offset) { _, line in
                    PoemLine(text: line)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(linesLabel)

            Spacer(minLength: 12)

            if session.yourTurn {
                writingArea(model: model)
            } else {
                theirTurn
            }

            Spacer(minLength: 24)
        }
        .onAppear { focused = session.yourTurn }
        .onChange(of: session.yourTurn) { _, mine in focused = mine }
    }

    // MARK: - Your turn

    @ViewBuilder
    private func writingArea(model: AppModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 16) {
            TextField("", text: $model.draft, axis: .vertical)
                .font(Theme.poem())
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .focused($focused)
                .submitLabel(.done)
                .accessibilityLabel("Your line, line \(session.currentLine + 1)")

            syllableHint

            if let err = model.submitError {
                Text(err)
                    .font(Theme.label)
                    .foregroundStyle(palette.accent)
                    .multilineTextAlignment(.center)
            }

            Button(action: model.submit) {
                Text("offer this line")
                    .font(Theme.poem(20))
                    .foregroundStyle(canSubmit(model) ? palette.ink : palette.secondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(palette.secondary.opacity(0.35), lineWidth: 1)
                    )
            }
            .disabled(!canSubmit(model))
        }
    }

    /// A quiet, optional nudge — never a gate. The 5-7-5 of a haiku is a gentle
    /// shape to lean toward, not a rule that holds your line back, so the hint
    /// stays recessive and is worded as an invitation (brief.v4.md §9).
    private var syllableHint: some View {
        let count = Syllables.count(model.draft)
        let target = session.currentTarget
        return Text(hintText(count: count, target: target))
            .font(Theme.label)
            .foregroundStyle(palette.secondary.opacity(0.7))
            .multilineTextAlignment(.center)
            .animation(.easeInOut(duration: 0.25), value: count)
            .accessibilityLabel(
                target.map { "About \($0) syllables suits this line. You've written \(count)." }
                    ?? "\(count) syllables"
            )
    }

    private func hintText(count: Int, target: Int?) -> String {
        guard let target else {
            return count == 0 ? " " : "\(count) syllables"
        }
        if count == 0 { return "a haiku rests near \(target) syllables here" }
        return "\(count) syllables · near \(target), if you like"
    }

    private func canSubmit(_ model: AppModel) -> Bool {
        !model.submitting && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Their turn

    private var theirTurn: some View {
        VStack(spacing: 12) {
            Text("the stranger is with the poem now")
                .font(Theme.chrome)
                .foregroundStyle(palette.secondary)
            Text("it's fine to put this down — you'll be told when there's a line for you")
                .font(Theme.label)
                .foregroundStyle(palette.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for the stranger to write their line.")
    }

    private var linesLabel: String {
        session.lines.isEmpty ? "No lines yet." : "The poem so far: " + session.lines.joined(separator: ". ")
    }
}
