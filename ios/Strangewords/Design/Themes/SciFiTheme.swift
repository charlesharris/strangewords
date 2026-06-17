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
        skyline(&ctx, cell: cell, cols: cols, rows: rows, horizon: horizon, color: palette.far, maxRise: 0.16, gapMax: 2, seed: 11, lit: palette.accent.opacity(0.5), frame: frame)
        skyline(&ctx, cell: cell, cols: cols, rows: rows, horizon: horizon + Int(Double(rows) * 0.06), color: palette.near, maxRise: 0.26, gapMax: 3, seed: 27, lit: palette.accent, frame: frame)
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

    /// A varied skyline: buildings of differing widths and (biased) heights, with
    /// setback upper tiers on the tall ones, blinking antennas, and a per-building
    /// window density so some towers are bright and others nearly dark.
    private func skyline(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int, horizon: Int, color: Color, maxRise: Double, gapMax: Int, seed: Int, lit: Color, frame: Int) {
        var col = 0
        while col < cols {
            let w = 2 + Int(Pixel.hash(seed + col, 1) * 5)                  // 2–6 wide
            let tall = Pixel.hash(seed + col, 2)                           // 0..1 height factor
            // Strong bias toward shorter buildings, with a few skyscrapers.
            let h = (0.03 + pow(tall, 2.2) * maxRise) * Double(rows)
            let baseTop = max(1, horizon - Int(h))

            block(&ctx, col: col, w: w, top: baseTop, bottom: rows, cell: cell, color, cols: cols)

            // A setback upper tier on taller, wider buildings.
            var crownTop = baseTop
            if tall > 0.55 && w >= 4 {
                let upTop = max(1, baseTop - Int(Double(rows) * 0.06 * tall))
                block(&ctx, col: col + 1, w: w - 2, top: upTop, bottom: baseTop, cell: cell, color, cols: cols)
                crownTop = upTop
            }

            // A thin antenna with a blinking beacon on the tallest towers.
            if tall > 0.78 {
                let ax = col + w / 2
                for r in max(1, crownTop - 3)..<crownTop { Pixel.fill(&ctx, ax, r, cell, color) }
                let blink = (frame / 3 + col) % 4 == 0
                Pixel.fill(&ctx, ax, max(0, crownTop - 4), cell, blink ? lit : color)
            }

            // Windows (night only), with per-building brightness.
            if palette.isDark {
                let density = Pixel.hash(seed + col, 5)
                if density > 0.25 {
                    var wy = baseTop + 2
                    while wy < rows - 1 {
                        var wx = col + 1
                        while wx < col + w - 1 {
                            if Pixel.hash(seed + wx * 7 + wy * 13, 9) < density {
                                Pixel.fill(&ctx, wx, wy, cell, lit)
                            }
                            wx += 2
                        }
                        wy += 2
                    }
                }
            }

            col += w + Int(Pixel.hash(seed + col, 6) * Double(gapMax + 1))
        }
    }

    private func block(_ ctx: inout GraphicsContext, col: Int, w: Int, top: Int, bottom: Int, cell: CGFloat, _ color: Color, cols: Int) {
        for c in col..<min(col + w, cols) where c >= 0 {
            for r in max(0, top)..<max(0, bottom) { Pixel.fill(&ctx, c, r, cell, color) }
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
            .padding(.horizontal, 28)

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

    /// A full-screen "derez": cells flare on in a random order and clear again,
    /// sweeping a neon pixel-dissolve across the whole scene while the text fades.
    private func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let p = min(1.0, t / duration)
        let cell = Pixel.cellSize(width: size.width, columns: 64)
        let cols = Int((size.width / cell).rounded(.up))
        let rows = Int((size.height / cell).rounded(.up))
        let neon = ctx.palette.accent
        let glow = ctx.palette.sun
        let window = 0.18
        for row in 0..<rows {
            for col in 0..<cols {
                let threshold = Pixel.hash(col * 131 + row * 977, 1) * (1 - window)
                let d = p - threshold
                if d < 0 || d > window { continue }
                if (Int(t * 16) + col * 3 + row * 7) % 4 == 0 { continue }   // flicker
                let k = 1 - abs(d / window - 0.5) * 2                         // brightness peaks mid-window
                let color = (Pixel.hash(col + row * 31, 2) > 0.82 ? glow : neon).opacity(0.45 + 0.55 * k)
                Pixel.fill(&c, col, row, cell, color)
            }
        }
    }
}
