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

    private var syllableHint: some View {
        let count = Syllables.count(model.draft)
        let target = session.currentTarget
        return HStack(spacing: 6) {
            Text("\(count)")
                .font(Theme.label)
                .foregroundStyle(palette.ink)
            if let target {
                Text("/ \(target) syllables")
                    .font(Theme.label)
                    .foregroundStyle(palette.secondary)
            }
        }
        .accessibilityLabel(target.map { "\(count) of about \($0) syllables" } ?? "\(count) syllables")
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
