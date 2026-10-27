import SwiftUI

/// The threshold: a single chosen step into the ritual, not an auto-queue
/// (brief.v4.md §5). No queue language, no chrome implying permanence.
struct ThresholdView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.sceneTheme) private var theme
    /// Sheet-open is view-local UI state, not model state.
    @State private var showSettings = false
    /// A fresh opening line each time the threshold appears.
    @State private var tagline = SplashLines.random()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Text("Strange Words")
                    .font(Theme.display(34))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                Text(tagline)
                    .font(Theme.chrome)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: model.begin) {
                Text("begin").font(Theme.poem(22))
            }
            .buttonStyle(.ritual)
            .accessibilityHint("Steps into the waiting room to be matched with a stranger.")
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Quiet chrome, top-leading: the dev chips own top-trailing.
        .overlay(alignment: .topLeading) { settingsGear }
        .sheet(isPresented: $showSettings) {
            // Re-injected explicitly rather than trusting sheet inheritance.
            SettingsView()
                .environment(\.palette, palette)
                .environment(\.sceneTheme, theme)
                .environment(model)
                .preferredColorScheme(palette.isDark ? .dark : .light)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.skyBottom)
        }
    }

    /// 44pt hit area; the 36pt backing circle and 20pt glyph put the glyph's
    /// visual left edge on the 28pt content margin.
    private var settingsGear: some View {
        Button { showSettings = true } label: {
            ZStack {
                Circle().fill(palette.onAccent.opacity(0.6)).frame(width: 36, height: 36)
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(palette.ink.opacity(0.8))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .offset(x: -12)
        .padding(.top, 8)
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens preferences, including writing with the robot poet.")
    }
}

/// Quieter than `.ritual`: opacity only, no scale.
private struct QuietPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
