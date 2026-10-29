import SwiftUI

/// A quiet way out of Compose, shown in both the your-turn and their-turn states.
///
/// Why it exists: during the 2026-10-27 TestFlight session a dead partner held the
/// user at "the stranger is with the poem now" with no exit, and `AppModel.resume()`
/// restored the trap on every relaunch (see
/// .planning/todos/pending/2026-10-27-add-leave-affordance-to-compose.md).
///
/// It reuses `AppModel.leave()` unchanged: that POSTs leave, dissolves locally to
/// `.dissolved(.ended)`, clears identity, and shows the plain farewell and then
/// "begin again".
///
/// It asks first because stepping away ends the poem for both writers and cannot
/// be undone.
///
/// The copy is partner-neutral on purpose: the same strings appear in human and
/// robot-poet sessions, so they never name the partner (Phase 5 D-04 voice rule).
struct StepAway: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var confirming = false

    var body: some View {
        Button {
            confirming = true
        } label: {
            Text(Self.label)
                .font(Theme.label)
                .foregroundStyle(palette.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityHint(Self.accessibilityHint)
        .confirmationDialog(Self.confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(Self.confirmAction, role: .destructive) {
                Haptics.soft()
                model.leave()
            }
            Button(Self.stayAction, role: .cancel) {}
        } message: {
            Text(Self.confirmMessage)
        }
    }

    // MARK: - Copy (pure, unit-tested)

    static let label = "step away"
    static let accessibilityHint = "Asks before letting this unfinished poem go. It will not be saved."
    static let confirmTitle = "step away from this poem?"
    static let confirmMessage = "the poem will dissolve unfinished and won't come back"
    static let confirmAction = "step away"
    static let stayAction = "stay with the poem"
}
