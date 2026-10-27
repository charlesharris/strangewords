import SwiftUI

/// The settings sheet: one switch, default OFF. Rows are children of a VStack so
/// later rows (safety, EULA) can append without a redesign.
///
/// The toggle writes straight through to `AppModel.allowBot`, which persists via
/// `SettingsStore` (Plan 02); the value applies to the next `begin()`. Nothing
/// here nudges: no prompt, badge or default-on (D-01).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    static let title = "settings"
    static let toggleTitle = "write with the robot poet"
    static let helperText = "if no one else arrives after a little while, a robot poet — software on our server, not a person — can write with you, and you'll always be told."

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 24) {
                header
                VStack(spacing: 16) {
                    Toggle(isOn: $model.allowBot) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.toggleTitle)
                                .font(Theme.chrome)
                                .foregroundStyle(palette.ink)
                            Text(Self.helperText)
                                .font(Theme.label)
                                .foregroundStyle(palette.ink.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .tint(palette.accent)
                    .padding(16)
                    .frame(minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16).fill(palette.onAccent.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16).stroke(palette.ink.opacity(0.15), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        ZStack {
            Text(Self.title)
                .font(Theme.poem(20))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text("close")
                        .font(Theme.chrome)
                        .foregroundStyle(palette.ink)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close settings")
            }
        }
    }
}
