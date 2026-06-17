import SwiftUI

/// A neon sci-fi look: a ringed planet over a city skyline of lit windows, and a
/// "derez" dissolution where the poem breaks into rising, flickering fragments.
/// Its three times of day read as dawn / bright day / neon night.
struct SciFiTheme: SceneTheme {
    let id = "sci-fi"
    let name = "sci-fi"

    func palette(_ timeOfDay: TimeOfDay) -> Palette {
        switch timeOfDay {
        case .morning:
            return Palette(
                skyTop: Color(0x243A6E), skyBottom: Color(0xE8A06A),
                ink: Color(0x14263F), secondary: Color(0x5E6E86),
                accent: Color(0x17B6C9), onAccent: Color(0xF4FBFF),
                sun: Color(0xFFE3B0), far: Color(0x33405F), near: Color(0x1B2740), isDark: false)
        case .afternoon:
            return Palette(
                skyTop: Color(0x2E6FB0), skyBottom: Color(0xC2E6F4),
                ink: Color(0x123040), secondary: Color(0x5C7A8C),
                accent: Color(0x0E9FB8), onAccent: Color(0xF7FCFF),
                sun: Color(0xFFF4D8), far: Color(0x6E8FA8), near: Color(0x3C5C70), isDark: false)
        case .night:
            return Palette(
                skyTop: Color(0x05060F), skyBottom: Color(0x1C1248),
                ink: Color(0xCFE8FF), secondary: Color(0x6E86B8),
                accent: Color(0x32E6E6), onAccent: Color(0x0A1430),
                sun: Color(0x9AD7FF), far: Color(0x101a3a), near: Color(0x070A1C), isDark: true)
        }
    }

    func background(_ timeOfDay: TimeOfDay, _ palette: Palette) -> AnyView {
        AnyView(SciFiScene(palette: palette, timeOfDay: timeOfDay))
    }

    var dissolution: any DissolutionEffect { SciFiDissolution() }
}

// MARK: - Scene

private struct SciFiScene: View {
    let palette: Palette
    let timeOfDay: TimeOfDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns: CGFloat = 64
    private let fps: Double = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let frame = reduceMotion ? 0 : Int(tl.date.timeIntervalSinceReferenceDate * fps)
                draw(&ctx, size: size, frame: frame)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, frame: Int) {
        let cell = Pixel.cellSize(width: size.width, columns: columns)
        let cols = Int((size.width / cell).rounded(.up))
        let rows = Int((size.height / cell).rounded(.up))
        let horizon = Int(Double(rows) * 0.66)

        Pixel.sky(&ctx, cell: cell, cols: cols, horizon: horizon, top: palette.skyTop, bottom: palette.skyBottom)
        if palette.isDark {
            Pixel.stars(&ctx, cell: cell, cols: cols, maxRow: Int(Double(horizon) * 0.9), count: 44, frame: frame,
                        bright: .white, dim: palette.secondary.opacity(0.5))
        }
        planet(&ctx, cell: cell, cols: cols, rows: rows)
        // Far skyline behind, near skyline in front.
        skyline(&ctx, cell: cell, cols: cols, rows: rows, horizon: horizon, color: palette.far, rise: 0.14, gap: 1, seed: 11, lit: palette.accent.opacity(0.5))
        skyline(&ctx, cell: cell, cols: cols, rows: rows, horizon: horizon + Int(Double(rows) * 0.05), color: palette.near, rise: 0.22, gap: 2, seed: 27, lit: palette.accent)
    }

    private func planet(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int) {
        let cx = Int(Double(cols) * 0.72), cy = Int(Double(rows) * 0.17), rad = 6
        // The ring (an ellipse); back half behind the disc, front half over it.
        var back: [(Int, Int)] = [], front: [(Int, Int)] = []
        let rx = Double(rad) * 2.0, ry = Double(rad) * 0.55
        for a in stride(from: 0.0, to: 360.0, by: 5.0) {
            let r = a * .pi / 180
            let ex = cx + Int((cos(r) * rx).rounded())
            let ey = cy + Int((sin(r) * ry).rounded())
            if sin(r) >= 0 { front.append((ex, ey)) } else { back.append((ex, ey)) }
        }
        let ringColor = palette.accent
        for (x, y) in back { Pixel.fill(&ctx, x, y, cell, ringColor.opacity(0.8)) }
        // Glow + disc.
        Pixel.ring(&ctx, cx: cx, cy: cy, inner: rad, outer: rad + 2, cell: cell, palette.sun.opacity(palette.isDark ? 0.12 : 0.22))
        Pixel.disc(&ctx, cx: cx, cy: cy, rad: rad, cell: cell, palette.sun)
        // A couple of darker bands across the planet.
        let band = palette.sun.mix(palette.skyTop, 0.35)
        for dy in [-2, 1] {
            for dx in -rad...rad where dx * dx + dy * dy <= rad * rad {
                Pixel.fill(&ctx, cx + dx, cy + dy, cell, band)
            }
        }
        for (x, y) in front { Pixel.fill(&ctx, x, y, cell, ringColor) }
    }

    /// A row of stepped buildings filled down to the bottom, with lit windows.
    private func skyline(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int, horizon: Int, color: Color, rise: Double, gap: Int, seed: Int, lit: Color) {
        var col = 0
        while col < cols {
            let w = 3 + Int(Pixel.hash(seed + col, 1) * 4)            // 3–6 wide
            let top = horizon - Int(Pixel.hash(seed + col, 2) * Double(rows) * rise)
            for c in col..<min(col + w, cols) {
                for r in max(0, top)..<rows { Pixel.fill(&ctx, c, r, cell, color) }
            }
            // Windows (night only) — a sparse lit grid.
            if palette.isDark {
                var wy = top + 2
                while wy < rows - 1 {
                    var wx = col + 1
                    while wx < col + w - 1 {
                        if Pixel.hash(seed + wx * 7 + wy * 13, 3) > 0.45 {
                            Pixel.fill(&ctx, wx, wy, cell, lit)
                        }
                        wx += 2
                    }
                    wy += 2
                }
            }
            col += w + gap
        }
    }
}

// MARK: - Dissolution (derez: rising, flickering fragments)

struct SciFiDissolution: DissolutionEffect {
    var duration: Double = 3.4
    func makeBody(_ ctx: DissolutionContext, onComplete: @escaping () -> Void) -> AnyView {
        AnyView(SciFiDissolutionView(ctx: ctx, duration: duration, onComplete: onComplete))
    }
}

private struct SciFiDissolutionView: View {
    let ctx: DissolutionContext
    let duration: Double
    let onComplete: () -> Void

    @State private var gone = false
    @State private var start: Date?
    private let cell: CGFloat = 7
    private static let count = 34

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                ForEach(Array(ctx.lines.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(Theme.poem())
                        .foregroundStyle(ctx.palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(gone ? 0 : 1)
                        .animation(.easeIn(duration: duration * 0.5).delay(Double(i) * duration * 0.12), value: gone)
                }
            }
            .frame(maxWidth: .infinity)

            if !ctx.reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 14.0)) { tl in
                    Canvas { c, size in
                        let t = start.map { tl.date.timeIntervalSince($0) } ?? 0
                        draw(&c, size: size, t: t)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            }
        }
        .onAppear { start = Date(); withAnimation { gone = true } }
        .task { try? await Task.sleep(for: .seconds(duration)); onComplete() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The poem is dissolving.")
    }

    private func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let neon = ctx.palette.accent
        let glow = ctx.palette.sun
        for i in 0..<Self.count {
            let delay = Pixel.hash(i, 7) * duration * 0.35
            let local = t - delay
            if local <= 0 { continue }
            let p = min(1.0, local / max(duration - delay, 0.001))

            let startX = Pixel.hash(i, 1) * Double(size.width)
            let startY = (0.34 + Pixel.hash(i, 2) * 0.32) * Double(size.height)
            let rise = p * Double(size.height) * 0.7
            let drift = sin(local * (1.5 + Pixel.hash(i, 3) * 2) + Pixel.hash(i, 4) * 6.28) * (10 + Pixel.hash(i, 5) * 30)

            let pcell = cell * (0.7 + Pixel.hash(i, 11) * 1.1)
            let qx = ((startX + drift) / Double(pcell)).rounded() * Double(pcell)
            let qy = ((startY - rise) / Double(pcell)).rounded() * Double(pcell)

            // Flicker on/off, and fade over the last third.
            let flicker = (Int(t * 14) + i * 3) % 3 != 0
            let fade = p < 0.66 ? 1.0 : max(0, 1 - (p - 0.66) / 0.34)
            let opacity = (flicker ? 1.0 : 0.25) * fade * (0.7 + Pixel.hash(i, 6) * 0.3)
            if opacity <= 0.02 { continue }

            let color = (i % 4 == 0 ? glow : neon).opacity(opacity)
            // Small fragment: 1 or 2 cells.
            let big = Pixel.hash(i, 8) > 0.6
            c.fill(Path(CGRect(x: qx, y: qy, width: pcell * (big ? 2 : 1), height: pcell)), with: .color(color))
        }
    }
}
