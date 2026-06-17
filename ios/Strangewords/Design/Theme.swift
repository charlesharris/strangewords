import SwiftUI

// MARK: - Color from hex

extension Color {
    init(_ hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

// MARK: - Time of day → palette

/// The app renders a day/night scene from the local time. Three directions to
/// begin with — morning, afternoon, night — drawn from the design boards in
/// docs/. Dynamic/seasonal scenes can grow from here later.
enum TimeOfDay: String {
    case morning, afternoon, night

    static func now(_ date: Date = Date(), calendar: Calendar = .current) -> TimeOfDay {
        // Dev/preview override: SW_FORCE_TOD=morning|afternoon|night.
        if let forced = ProcessInfo.processInfo.environment["SW_FORCE_TOD"],
           let tod = TimeOfDay(rawValue: forced) {
            return tod
        }
        switch calendar.component(.hour, from: date) {
        case 5..<12:  return .morning
        case 12..<18: return .afternoon
        default:      return .night
        }
    }

    /// Next in the daily cycle (morning → afternoon → night → …). Used by the
    /// dev time-of-day toggle to preview each backdrop.
    var next: TimeOfDay {
        switch self {
        case .morning:   return .afternoon
        case .afternoon: return .night
        case .night:     return .morning
        }
    }

    var palette: Palette {
        switch self {
        case .morning:
            return Palette(
                skyTop: Color(0xF7CDCB), skyBottom: Color(0xFCEFE6),
                ink: Color(0x4E3B34), secondary: Color(0x927A70),
                accent: Color(0xE2848C), onAccent: Color(0xFFFFFF),
                sun: Color(0xFFD9B0), far: Color(0xE7B7B2), near: Color(0xD49A92),
                isDark: false)
        case .afternoon:
            return Palette(
                skyTop: Color(0xEBCFCB), skyBottom: Color(0xFAEDE6),
                ink: Color(0x4C4741), secondary: Color(0x8E837C),
                accent: Color(0xD98890), onAccent: Color(0xFFFFFF),
                sun: Color(0xFFF1D8), far: Color(0xDCB1AC), near: Color(0xC79A91),
                isDark: false)
        case .night:
            return Palette(
                skyTop: Color(0x1E2138), skyBottom: Color(0x3B3551),
                ink: Color(0xECE5DB), secondary: Color(0xA8A1B4),
                accent: Color(0xC9B2CB), onAccent: Color(0x2A2440),
                sun: Color(0xEDE7D6), far: Color(0x2A2E50), near: Color(0x15162C),
                isDark: true)
        }
    }
}

/// A resolved color set for the current scene. `sun` doubles as the moon at night.
struct Palette {
    let skyTop: Color
    let skyBottom: Color
    let ink: Color        // primary text
    let secondary: Color  // receding chrome / hints
    let accent: Color     // the single warm accent (strawberry/rose/wisteria)
    let onAccent: Color
    let sun: Color        // celestial body color
    let far: Color        // distant ridge silhouette
    let near: Color       // foreground hill silhouette
    let isDark: Bool
}

// MARK: - Environment plumbing

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = TimeOfDay.morning.palette
}
private struct TimeOfDayKey: EnvironmentKey {
    static let defaultValue = TimeOfDay.morning
}
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    var timeOfDay: TimeOfDay {
        get { self[TimeOfDayKey.self] }
        set { self[TimeOfDayKey.self] = newValue }
    }
}

// MARK: - Typography

/// Two voices, both bundled (Resources/Fonts, see project.yml UIAppFonts):
/// **Fraunces** — a high-contrast display serif standing in the spirit of the
/// board's Larken — carries the poem and the ritual chrome; it optically sizes
/// itself as the point size changes (its `opsz` axis is left free). **Inter**
/// is the quiet body/sans for hints and secondary copy. Sizes are declared
/// `relativeTo:` a text style so they scale with Dynamic Type.
enum Theme {
    /// The poem voice and the warm ritual buttons.
    static func poem(_ size: CGFloat = 26) -> Font {
        .custom("Fraunces", size: size, relativeTo: .title2)
    }
    /// The serif in italic — for the rare turned phrase.
    static func poemItalic(_ size: CGFloat = 26) -> Font {
        .custom("Fraunces", size: size, relativeTo: .title2).italic()
    }
    /// A weightier display cut for the single largest title.
    static func display(_ size: CGFloat = 30) -> Font {
        .custom("Fraunces SemiBold", size: size, relativeTo: .largeTitle)
    }
    static let chrome = Font.custom("Inter", size: 15, relativeTo: .subheadline)
    static let label  = Font.custom("Inter", size: 13, relativeTo: .caption)
}

/// A line of poem in the shared serif voice, colored by the current palette.
struct PoemLine: View {
    @Environment(\.palette) private var palette
    let text: String
    var dim: Bool = false
    var body: some View {
        Text(text)
            .font(Theme.poem())
            .foregroundStyle(dim ? palette.secondary : palette.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}
