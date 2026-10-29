import Testing
import Foundation
import SwiftUI
import UIKit
@testable import Strangewords

/// Proves, with WCAG 2.x contrast math, that every non-poem piece of text in the app
/// is readable over what it actually renders on, in all nine theme x time-of-day
/// palettes (quick-261029-l7k). Static palette data only: no AppModel, Backend,
/// TokenStore, UserDefaults or poem text is touched, so nothing here can persist
/// identity or poem content (anonymity model), and nothing waits on a clock.
///
/// ## The model
///
/// - Math: sRGB channels linearized, `L = 0.2126R + 0.7152G + 0.0722B`,
///   `ratio = (Lhi + 0.05) / (Llo + 0.05)`. Opacity and backings composite
///   source-over in gamma-encoded sRGB, which is the default CoreAnimation blend.
/// - Thresholds: normal text 4.5; large text 3.0 (>= 24pt, or >= 19pt at semibold or
///   heavier, with 1 iOS pt read as 1 CSS px, the conservative reading); non-text
///   controls 3.0. Sizes are the declared defaults; Dynamic Type only enlarges text,
///   which only relaxes the threshold.
/// - Each surface is measured against the SET of colors it can sit on (sky bands that
///   meet its vertical range, ground silhouettes, the phase dusk, its own backing). The
///   ratio is the minimum over that set. `best` is the highest minimum ANY gray text
///   color could reach there; a cell is FIXABLE iff `best >= threshold`.
///
/// ## Limits (stated so a green run is not over-read)
///
/// - Reference device: iPhone 17 (402 x 874pt). Smaller screens shift centered copy up
///   by about 2-5% and can graze one more sky band.
/// - Point decorations are excluded: stars, motes, clouds, blossoms, lit windows,
///   antennas and beacons, celestial discs and glows.
/// - The Bayer-dithered sky shows two adjacent bands on any row. Every band that meets
///   the surface's range is treated as its own backdrop, per cell, which is strict.
/// - The radial vignette stays clear within 0.45 x maxR of the center, so it is treated
///   as clear for centered copy; only the phase dusk and its linear ground layer count.
/// - Dissolution text (a fade-out animation), disabled ritual labels (WCAG 1.4.3 exempts
///   inactive components), the system confirmationDialog and the dev chips (dev builds
///   only) are not measured.
struct ContrastTests {

    // MARK: - 1. The math itself

    @Test func wcagMathMatchesReferenceValues() {
        let white = RGB(hex: 0xFFFFFF), black = RGB(hex: 0x000000)
        #expect(abs(contrast(black, white) - 21.0) < 1e-9)
        #expect(contrast(RGB(hex: 0x4E3B34), RGB(hex: 0x4E3B34)) == 1.0)
        let ratio767676 = contrast(RGB(hex: 0x767676), white)
        #expect(abs(ratio767676 - 4.54) < 0.01, "0x767676 on white measured \(ratio767676)")
        #expect(contrast(RGB(hex: 0x777777), white) < 4.5)
        // Compositing is in gamma-encoded sRGB: half black over white is the 0.5 gray.
        let half = composite(black, 0.5, over: white)
        #expect(abs(half.r - 0.5) < 1e-9 && abs(half.g - 0.5) < 1e-9 && abs(half.b - 0.5) < 1e-9)
    }

    // MARK: - 2. Backgrounds and scene-borrowed colors do not move

    /// The scenes borrow ink (the cherry branch) and night secondary (the dim stars), so
    /// pinning them keeps every scene pixel identical. Reading the hex back through
    /// UIColor also proves the extraction is exact. These are the only copied hex
    /// tables in this file; everything else resolves through `Themes.all`.
    @Test func sceneColorsAreUnchanged() {
        for cell in Self.cells {
            let pin = Self.pins["\(cell.theme)|\(cell.tod.rawValue)"]
            #expect(pin != nil, "no pin for \(cell.theme) \(cell.tod.rawValue)")
            guard let pin else { continue }
            let p = cell.palette
            let label = "\(cell.theme) \(cell.tod.rawValue)"
            #expect(RGB(p.skyTop).hex == pin.skyTop, "\(label) skyTop")
            #expect(RGB(p.skyBottom).hex == pin.skyBottom, "\(label) skyBottom")
            #expect(RGB(p.sun).hex == pin.sun, "\(label) sun")
            #expect(RGB(p.far).hex == pin.far, "\(label) far")
            #expect(RGB(p.near).hex == pin.near, "\(label) near")
            #expect(RGB(p.accent).hex == pin.accent, "\(label) accent")
            #expect(RGB(p.onAccent).hex == pin.onAccent, "\(label) onAccent")
            #expect(RGB(p.ink).hex == pin.ink, "\(label) ink")
            #expect(p.isDark == pin.isDark, "\(label) isDark")
            if let secondary = pin.secondary {
                #expect(RGB(p.secondary).hex == secondary, "\(label) secondary")
            }
        }
    }

    // MARK: - 3. Secondary stays the quieter voice

    @Test func textHierarchyIsPreserved() {
        for cell in Self.cells {
            let p = cell.palette
            let ls = luminance(RGB(p.secondary)), li = luminance(RGB(p.ink))
            let label = "\(cell.theme) \(cell.tod.rawValue)"
            if p.isDark {
                #expect(ls < li, "\(label): night secondary must stay darker than ink")
            } else {
                #expect(ls > li, "\(label): day secondary must stay lighter than ink")
            }
            let sep = contrast(RGB(p.secondary), RGB(p.ink))
            #expect(sep >= 1.3, "\(label): secondary/ink separation \(sep) < 1.3")
        }
    }

    // MARK: - 4-6. The three claims

    @Test func nonPoemTextMeetsAA() {
        for cell in Self.cells {
            for s in Self.inventory where !Self.poemIDs.contains(s.id) {
                let r = Self.evaluate(s, cell)
                #expect(r.pass,
                        "\(cell.theme) \(cell.tod.rawValue) \(s.id): \(Self.fmt(r.ratio)) < \(Self.fmt(r.threshold))")
            }
        }
    }

    /// Poem text is large, so 3:1 is its AA bar; dropping under it is failing badly.
    @Test func poemTextNeverFailsBadly() {
        for cell in Self.cells {
            for s in Self.inventory where Self.poemIDs.contains(s.id) {
                let r = Self.evaluate(s, cell)
                #expect(r.ratio >= 3.0,
                        "\(cell.theme) \(cell.tod.rawValue) \(s.id): \(Self.fmt(r.ratio)) < 3.00")
            }
        }
    }

    @Test func everySurfaceSitsWhereSomeTextColorCanPass() {
        for cell in Self.cells {
            for s in Self.inventory {
                let r = Self.evaluate(s, cell)
                #expect(r.fixable,
                        "\(cell.theme) \(cell.tod.rawValue) \(s.id): best any-color ratio \(Self.fmt(r.best)) < \(Self.fmt(r.threshold))")
            }
        }
    }

    // MARK: - 7. The sky backing is earned, not blanket

    /// `backsSkyText` may be true only where no text color at all can reach 4.5:1 over
    /// the unbacked sky and skyline (sci-fi morning and afternoon); everywhere else a
    /// text-color fix is enough, and a blanket pill would be needless chrome.
    @Test func skyBackingOnlyWhereNoTextColorCanPass() {
        for cell in Self.cells {
            let unbacked = Surface(id: "sky.probe", role: .ink, opacity: 1.0, size: .normal,
                                   placement: .sky, depth: 0, backing: .none)
            let best = Self.bestAnyGray(over: Self.backdrops(unbacked, cell))
            #expect(cell.palette.backsSkyText == (best < 4.5),
                    "\(cell.theme) \(cell.tod.rawValue): backsSkyText=\(cell.palette.backsSkyText) but best any-color ratio over the unbacked sky is \(Self.fmt(best))")
        }
    }

    // MARK: - 8. The printed matrix

    @Test func contrastMatrix() {
        #expect(Self.inventory.count == 23)
        #expect(Set(Self.inventory.map(\.id)).count == 23, "surface ids must be unique")
        var lines: [String] = []
        for cell in Self.cells {
            for s in Self.inventory {
                let r = Self.evaluate(s, cell)
                lines.append([
                    "CONTRAST", cell.theme, cell.tod.rawValue, s.id, s.role.rawValue,
                    Self.fmt(r.ratio), Self.fmt(r.threshold), r.pass ? "PASS" : "FAIL",
                    Self.fmt(r.best), r.fixable ? "FIXABLE" : "INFEASIBLE",
                ].joined(separator: "|"))
            }
        }
        #expect(lines.count == 207)
        print(lines.joined(separator: "\n"))
        fflush(stdout)
    }

    // MARK: - Palettes (from the real registry, never copied)

    struct Cell {
        let theme: String
        let tod: TimeOfDay
        let palette: Palette
    }

    static let times: [TimeOfDay] = [.morning, .afternoon, .night]

    static let cells: [Cell] = Themes.all.flatMap { theme in
        times.map { Cell(theme: theme.id, tod: $0, palette: theme.palette($0)) }
    }

    // MARK: - Surface inventory

    enum Role: String { case ink, secondary, accent }

    enum Size {
        case normal, large, nonText
        var threshold: Double { self == .normal ? 4.5 : 3.0 }
    }

    enum Placement {
        /// Sky copy, y in [0.32, 0.52] of screen height.
        case sky
        /// The lower screen, y in [0.30, 1.00].
        case low
        /// A control that carries its own onAccent backing at this opacity.
        case chrome(Double)
        /// The settings sheet's opaque skyBottom.
        case sheet
        /// A settings card: onAccent 0.6 over skyBottom.
        case card
    }

    enum Backing {
        case none
        /// Backed in every palette.
        case always
        /// Backed iff `Palette.backsSkyText`.
        case skyFlag
    }

    struct Surface {
        let id: String
        let role: Role
        let opacity: Double
        let size: Size
        let placement: Placement
        /// SceneDepthOverlay strength for the phase this surface lives in.
        let depth: Double
        let backing: Backing
    }

    /// Poem text (PoemLine and the Compose draft): held to 3:1, not the non-poem bar.
    static let poemIDs: Set<String> = ["poem.line", "compose.draft"]

    /// 23 surfaces, in the order the matrix prints them. Values are the styling the
    /// views render today.
    static let inventory: [Surface] = [
        Surface(id: "threshold.title", role: .ink, opacity: 1.0, size: .large, placement: .sky, depth: 0, backing: .skyFlag),
        Surface(id: "threshold.tagline", role: .secondary, opacity: 1.0, size: .normal, placement: .sky, depth: 0, backing: .skyFlag),
        Surface(id: "waiting.status", role: .secondary, opacity: 1.0, size: .normal, placement: .sky, depth: 0, backing: .none),
        Surface(id: "waiting.botLine", role: .secondary, opacity: 0.8, size: .normal, placement: .sky, depth: 0, backing: .none),
        Surface(id: "dissolved.keepsakeLead", role: .secondary, opacity: 1.0, size: .normal, placement: .sky, depth: 1.0, backing: .none),
        Surface(id: "dissolved.keepsakeName", role: .ink, opacity: 1.0, size: .large, placement: .sky, depth: 1.0, backing: .none),
        Surface(id: "dissolved.keepsakeKind", role: .secondary, opacity: 1.0, size: .normal, placement: .sky, depth: 1.0, backing: .none),
        Surface(id: "dissolved.farewell", role: .ink, opacity: 1.0, size: .normal, placement: .sky, depth: 1.0, backing: .none),
        Surface(id: "poem.line", role: .ink, opacity: 1.0, size: .large, placement: .sky, depth: 0.70, backing: .skyFlag),
        Surface(id: "compose.draft", role: .ink, opacity: 1.0, size: .large, placement: .low, depth: 0.22, backing: .none),
        Surface(id: "compose.syllableHint", role: .secondary, opacity: 0.7, size: .normal, placement: .low, depth: 0.22, backing: .none),
        Surface(id: "compose.submitError", role: .accent, opacity: 1.0, size: .normal, placement: .low, depth: 0.22, backing: .none),
        Surface(id: "compose.theirTurnPrimary", role: .secondary, opacity: 1.0, size: .normal, placement: .low, depth: 0.22, backing: .none),
        Surface(id: "compose.theirTurnSecondary", role: .secondary, opacity: 0.8, size: .normal, placement: .low, depth: 0.22, backing: .none),
        Surface(id: "compose.stepAway", role: .secondary, opacity: 1.0, size: .normal, placement: .low, depth: 0.22, backing: .none),
        Surface(id: "waiting.stepBackOut", role: .secondary, opacity: 1.0, size: .normal, placement: .low, depth: 0, backing: .none),
        Surface(id: "ritual.label", role: .ink, opacity: 1.0, size: .normal, placement: .chrome(0.85), depth: 1.0, backing: .none),
        Surface(id: "presence.chip", role: .ink, opacity: 1.0, size: .normal, placement: .chrome(0.6), depth: 0, backing: .none),
        Surface(id: "threshold.gear", role: .ink, opacity: 0.8, size: .nonText, placement: .chrome(0.6), depth: 0, backing: .none),
        Surface(id: "settings.title", role: .ink, opacity: 1.0, size: .normal, placement: .sheet, depth: 0, backing: .none),
        Surface(id: "settings.close", role: .ink, opacity: 1.0, size: .normal, placement: .sheet, depth: 0, backing: .none),
        Surface(id: "settings.rowText", role: .ink, opacity: 1.0, size: .normal, placement: .card, depth: 0, backing: .none),
        Surface(id: "settings.helper", role: .ink, opacity: 0.85, size: .normal, placement: .card, depth: 0, backing: .none),
    ]

    // MARK: - The backdrop model

    /// Horizon as a fraction of screen height, per theme. Sources:
    /// nature `Painter.draw` farHorizon 0.62 (PixelScene.swift); sci-fi `SciFiScene`
    /// horizon 0.66; fantasy `FantasyScene` farHorizon 0.64.
    static let horizons: [String: Double] = ["nature": 0.62, "sci-fi": 0.66, "fantasy": 0.64]

    static let skyRange: ClosedRange<Double> = 0.32...0.52
    static let lowRange: ClosedRange<Double> = 0.30...1.00

    /// SceneDepthOverlay's dusk tone (RootView.swift).
    static func duskColor(_ p: Palette) -> RGB { RGB(hex: p.isDark ? 0x070914 : 0x4E2433) }

    /// Sky bands present in a vertical range. Rows are Bayer-dithered between band
    /// floor(g) and floor(g)+1 where g = row / (horizon - 1) * 4, so band k appears
    /// iff the range of g meets the open interval (k-1, k+1).
    static func bandIndices(theme: String, range: ClosedRange<Double>) -> [Int] {
        guard let h = horizons[theme] else { return [] }
        let g0 = min(max(range.lowerBound / h * 4, 0), 4)
        let g1 = min(max(range.upperBound / h * 4, 0), 4)
        return (0...4).filter { Double($0) + 1 > g0 && Double($0) - 1 < g1 }
    }

    /// The scene colors a placement can sit over, before dusk and backing. Sky bands
    /// are built with the scene's own `Color.mix`, never re-implemented.
    static func sceneColors(_ placement: Placement, _ cell: Cell) -> [RGB] {
        let p = cell.palette
        func bands(_ ks: [Int]) -> [RGB] {
            ks.map { RGB(p.skyTop.mix(p.skyBottom, Double($0) / 4)) }
        }
        let ground = [RGB(p.far), RGB(p.near)]
        switch placement {
        case .sky:
            // The sci-fi skyline rises into the copy column; nature's ridges and the
            // fantasy castle start below it.
            return bands(bandIndices(theme: cell.theme, range: skyRange)) + (cell.theme == "sci-fi" ? ground : [])
        case .low:
            return bands(bandIndices(theme: cell.theme, range: lowRange)) + ground
        case .chrome:
            return bands([0, 1, 2, 3, 4]) + ground
        case .sheet:
            return [RGB(p.skyBottom)]
        case .card:
            return [composite(RGB(p.onAccent), Legibility0.cardOpacity, over: RGB(p.skyBottom))]
        }
    }

    /// Dusk strength over the placement: the linear ground layer reaches 0.02 by
    /// y = 0.52, and 0.5 at the bottom edge.
    static func duskAlpha(_ placement: Placement, depth: Double) -> Double {
        switch placement {
        case .sky: return 0.02 * depth
        case .low, .chrome: return 0.5 * depth
        case .sheet, .card: return 0
        }
    }

    /// Whether the surface renders on the shared onAccent legibility backing for this
    /// palette.
    static func isBacked(_ s: Surface, _ p: Palette) -> Bool {
        switch s.backing {
        case .none: return false
        case .always: return true
        case .skyFlag: return p.backsSkyText
        }
    }

    /// Everything a surface's text can sit on: scene colors with the phase dusk
    /// first, then the control's own backing or the legibility backing.
    static func backdrops(_ s: Surface, _ cell: Cell) -> [RGB] {
        let p = cell.palette
        let dusk = duskColor(p)
        let a = duskAlpha(s.placement, depth: s.depth)
        return sceneColors(s.placement, cell).map { scene in
            let dusked = a > 0 ? composite(dusk, a, over: scene) : scene
            switch s.placement {
            case .chrome(let o):
                return composite(RGB(p.onAccent), o, over: dusked)
            case .sky, .low:
                return isBacked(s, p) ? composite(RGB(p.onAccent), Legibility.backingOpacity, over: dusked) : dusked
            case .sheet, .card:
                return dusked
            }
        }
    }

    struct Result {
        let ratio: Double
        let threshold: Double
        let best: Double
        var pass: Bool { ratio >= threshold }
        var fixable: Bool { best >= threshold }
    }

    static func roleColor(_ role: Role, _ p: Palette) -> RGB {
        switch role {
        case .ink: return RGB(p.ink)
        case .secondary: return RGB(p.secondary)
        case .accent: return RGB(p.accent)
        }
    }

    static func evaluate(_ s: Surface, _ cell: Cell) -> Result {
        let set = backdrops(s, cell)
        let text = roleColor(s.role, cell.palette)
        let ratio = set.map { contrast(composite(text, s.opacity, over: $0), $0) }.min() ?? 0
        return Result(ratio: ratio, threshold: s.size.threshold, best: bestAnyGray(over: set))
    }

    /// The highest minimum contrast any full-opacity gray text could reach over `set`.
    static func bestAnyGray(over set: [RGB]) -> Double {
        (0...255).map { v -> Double in
            let g = Double(v) / 255
            let gray = RGB(r: g, g: g, b: g)
            return set.map { contrast(gray, $0) }.min() ?? 0
        }.max() ?? 0
    }

    static func fmt(_ x: Double) -> String { String(format: "%.2f", x) }

    // MARK: - Pins (HEAD hex values)

    struct Pin {
        let skyTop, skyBottom, ink, accent, onAccent, sun, far, near: UInt
        let isDark: Bool
        var secondary: UInt?
    }

    static let pins: [String: Pin] = [
        "nature|morning": Pin(skyTop: 0xF7CDCB, skyBottom: 0xFCEFE6, ink: 0x4E3B34, accent: 0xE2848C, onAccent: 0xFFFFFF,
                              sun: 0xFFD9B0, far: 0xE7B7B2, near: 0xD49A92, isDark: false),
        "nature|afternoon": Pin(skyTop: 0xEBCFCB, skyBottom: 0xFAEDE6, ink: 0x4C4741, accent: 0xD98890, onAccent: 0xFFFFFF,
                                sun: 0xFFF1D8, far: 0xDCB1AC, near: 0xC79A91, isDark: false),
        "nature|night": Pin(skyTop: 0x1E2138, skyBottom: 0x3B3551, ink: 0xECE5DB, accent: 0xC9B2CB, onAccent: 0x2A2440,
                            sun: 0xEDE7D6, far: 0x2A2E50, near: 0x15162C, isDark: true, secondary: 0xA8A1B4),
        "sci-fi|morning": Pin(skyTop: 0x243A6E, skyBottom: 0xE8A06A, ink: 0x14263F, accent: 0x17B6C9, onAccent: 0xF4FBFF,
                              sun: 0xFFE3B0, far: 0x33405F, near: 0x1B2740, isDark: false),
        "sci-fi|afternoon": Pin(skyTop: 0x2E6FB0, skyBottom: 0xC2E6F4, ink: 0x123040, accent: 0x0E9FB8, onAccent: 0xF7FCFF,
                                sun: 0xFFF4D8, far: 0x6E8FA8, near: 0x3C5C70, isDark: false),
        "sci-fi|night": Pin(skyTop: 0x05060F, skyBottom: 0x1C1248, ink: 0xCFE8FF, accent: 0x32E6E6, onAccent: 0x0A1430,
                            sun: 0x9AD7FF, far: 0x101A3A, near: 0x070A1C, isDark: true, secondary: 0x6E86B8),
        "fantasy|morning": Pin(skyTop: 0x6E7FB0, skyBottom: 0xF0D9E6, ink: 0x35264A, accent: 0xB07AD0, onAccent: 0xFDF6FF,
                               sun: 0xFFE9C0, far: 0x9A86B8, near: 0x6E5E8E, isDark: false),
        "fantasy|afternoon": Pin(skyTop: 0x8FA0D8, skyBottom: 0xEAE6F4, ink: 0x3A2F52, accent: 0xA86FD0, onAccent: 0xFCF8FF,
                                 sun: 0xFFF0CE, far: 0x9E8FC0, near: 0x6E5F94, isDark: false),
        "fantasy|night": Pin(skyTop: 0x150E2E, skyBottom: 0x3C2A63, ink: 0xF3E9D2, accent: 0xCBA6F2, onAccent: 0x251A40,
                             sun: 0xFFE6A8, far: 0x2A1F4A, near: 0x140D2C, isDark: true, secondary: 0xB9A8D6),
    ]
}

// MARK: - Color math

/// An sRGB color, gamma-encoded, channels 0...1.
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
}

extension RGB {
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b))
    }

    init(hex: UInt) {
        self.init(r: Double((hex >> 16) & 0xff) / 255,
                  g: Double((hex >> 8) & 0xff) / 255,
                  b: Double(hex & 0xff) / 255)
    }

    var hex: UInt {
        (UInt((r * 255).rounded()) << 16) | (UInt((g * 255).rounded()) << 8) | UInt((b * 255).rounded())
    }
}

func linearize(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

func luminance(_ c: RGB) -> Double {
    0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
}

func contrast(_ a: RGB, _ b: RGB) -> Double {
    let la = luminance(a), lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// Source-over in gamma-encoded sRGB: `out = a * fg + (1 - a) * bg` per channel.
func composite(_ fg: RGB, _ alpha: Double, over bg: RGB) -> RGB {
    RGB(r: alpha * fg.r + (1 - alpha) * bg.r,
        g: alpha * fg.g + (1 - alpha) * bg.g,
        b: alpha * fg.b + (1 - alpha) * bg.b)
}

/// The settings card's own recipe (SettingsView.settingsRowCard): onAccent at 0.6.
/// The legibility backing's opacity comes from the production `Legibility` constant.
enum Legibility0 {
    static let cardOpacity = 0.6
}
