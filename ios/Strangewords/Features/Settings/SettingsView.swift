import SwiftUI

/// The settings sheet: two rows, the robot-poet switch (default OFF) and the
/// scenery choice. Rows are children of a VStack so later rows (safety, EULA) can
/// append without a redesign.
///
/// Both rows write straight through to `AppModel` (`allowBot`, `themeID`), which
/// persists via `SettingsStore`. The robot-poet value applies to the next
/// `begin()`; a scenery pick repaints the app at once. Nothing here nudges: no
/// prompt, badge or default-on (D-01).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    static let title = "settings"
    static let toggleTitle = "write with the robot poet"
    static let helperText = "if no one else arrives after a little while, a robot poet — software on our server, not a person — can write with you, and you'll always be told."

    // MARK: - Copy (pinned by ThemeSelectionTests)

    static let themeTitle = "scenery"
    static let themeHelper = "the world your poem is written in. only you see it."

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
                    .settingsRowCard(palette)

                    sceneryCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }

    /// The scenery row: one option per registered theme, so a theme added to the
    /// registry appears here on its own. Ink glyphs, not accent: accent is reserved
    /// for the robot-poet switch's on-tint.
    private var sceneryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.themeTitle)
                    .font(Theme.chrome)
                    .foregroundStyle(palette.ink)
                Text(Self.themeHelper)
                    .font(Theme.label)
                    .foregroundStyle(palette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 4) {
                ForEach(Themes.all, id: \.id) { theme in
                    sceneryOption(theme)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsRowCard(palette)
    }

    private func sceneryOption(_ theme: any SceneTheme) -> some View {
        let selected = model.themeID == theme.id
        return Button {
            model.themeID = theme.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.chrome)
                    .foregroundStyle(palette.ink)
                    .accessibilityHidden(true)
                Text(theme.name)
                    .font(Theme.chrome)
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

private extension View {
    /// The shared card recipe of the settings rows (Phase 5 UI-SPEC Surface 1).
    func settingsRowCard(_ palette: Palette) -> some View {
        self
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
