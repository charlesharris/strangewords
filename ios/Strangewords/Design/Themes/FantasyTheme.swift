import SwiftUI

/// An enchanted look: twin moons over a distant castle on misty hills, with
/// drifting sparkle motes, and a dissolution where the poem rises away as
/// glowing, twinkling motes. Times of day read as misty dawn / soft day /
/// magical night.
struct FantasyTheme: SceneTheme {
    let id = "fantasy"
    let name = "fantasy"

    func palette(_ timeOfDay: TimeOfDay) -> Palette {
        switch timeOfDay {
        case .morning:
            return Palette(
                skyTop: Color(0x6E7FB0), skyBottom: Color(0xF0D9E6),
                ink: Color(0x35264A), secondary: Color(0x7B6E92),
                accent: Color(0xB07AD0), onAccent: Color(0xFDF6FF),
                sun: Color(0xFFE9C0), far: Color(0x9A86B8), near: Color(0x6E5E8E), isDark: false)
        case .afternoon:
            return Palette(
                skyTop: Color(0x8FA0D8), skyBottom: Color(0xEAE6F4),
                ink: Color(0x3A2F52), secondary: Color(0x7E7596),
                accent: Color(0xA86FD0), onAccent: Color(0xFCF8FF),
                sun: Color(0xFFF0CE), far: Color(0x9E8FC0), near: Color(0x6E5F94), isDark: false)
        case .night:
            return Palette(
                skyTop: Color(0x150E2E), skyBottom: Color(0x3C2A63),
                ink: Color(0xF3E9D2), secondary: Color(0xB9A8D6),
                accent: Color(0xCBA6F2), onAccent: Color(0x251A40),
                sun: Color(0xFFE6A8), far: Color(0x2A1F4A), near: Color(0x140D2C), isDark: true)
        }
    }

    func background(_ timeOfDay: TimeOfDay, _ palette: Palette) -> AnyView {
        AnyView(FantasyScene(palette: palette, timeOfDay: timeOfDay))
    }

    var dissolution: any DissolutionEffect { FantasyDissolution() }
}

// MARK: - Scene

private struct FantasyScene: View {
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
        let farHorizon = Int(Double(rows) * 0.64)
        let nearHorizon = Int(Double(rows) * 0.78)

        Pixel.sky(&ctx, cell: cell, cols: cols, horizon: farHorizon, top: palette.skyTop, bottom: palette.skyBottom)
        if palette.isDark {
            Pixel.stars(&ctx, cell: cell, cols: cols, maxRow: Int(Double(farHorizon) * 0.9), count: 34, frame: frame,
                        bright: .white, dim: palette.secondary.opacity(0.5))
        }
        moons(&ctx, cell: cell, cols: cols, rows: rows)
        motes(&ctx, cell: cell, cols: cols, rows: rows, horizon: farHorizon, frame: frame)
        // Far ridge, castle on it, then the near hill in front.
        Pixel.ridge(&ctx, cols: cols, rows: rows, cell: cell, baseRow: farHorizon, amp: 2, wavelength: 7, phase: 0.6, palette.far)
        castle(&ctx, cell: cell, cols: cols, baseRow: farHorizon)
        Pixel.ridge(&ctx, cols: cols, rows: rows, cell: cell, baseRow: nearHorizon, amp: 2.6, wavelength: 5, phase: 2.2, palette.near)
    }

    private func moons(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int) {
        let cx = Int(Double(cols) * 0.74), cy = Int(Double(rows) * 0.16)
        if palette.isDark {
            // A large moon and a smaller companion.
            Pixel.ring(&ctx, cx: cx, cy: cy, inner: 5, outer: 7, cell: cell, palette.sun.opacity(0.12))
            Pixel.disc(&ctx, cx: cx, cy: cy, rad: 5, cell: cell, palette.sun)
            let scx = Int(Double(cols) * 0.60), scy = Int(Double(rows) * 0.09)
            Pixel.ring(&ctx, cx: scx, cy: scy, inner: 2, outer: 3, cell: cell, palette.sun.opacity(0.12))
            Pixel.disc(&ctx, cx: scx, cy: scy, rad: 2, cell: cell, palette.sun)
        } else {
            Pixel.ring(&ctx, cx: cx, cy: cy, inner: 6, outer: 8, cell: cell, palette.sun.opacity(0.25))
            Pixel.disc(&ctx, cx: cx, cy: cy, rad: 6, cell: cell, palette.sun)
        }
    }

    /// A small distant castle silhouette standing on the far ridge: a battlemented
    /// tower with a thin spire and a pennant.
    private func castle(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, baseRow: Int) {
        let color = palette.near                // darkest tone reads as a silhouette
        let bx = Int(Double(cols) * 0.30)
        let tw = 4
        let top = baseRow - 10
        // Tower body.
        for c in bx..<(bx + tw) {
            for r in top..<baseRow { Pixel.fill(&ctx, c, r, cell, color) }
        }
        // Crenellations along the top.
        for c in stride(from: bx, to: bx + tw, by: 2) { Pixel.fill(&ctx, c, top - 1, cell, color) }
        // A thin spire and a pennant.
        let sx = bx + tw / 2
        for r in (top - 4)..<top { Pixel.fill(&ctx, sx, r, cell, color) }
        Pixel.fill(&ctx, sx + 1, top - 4, cell, palette.accent)
        Pixel.fill(&ctx, sx + 2, top - 4, cell, palette.accent)
        // A lit window at night.
        if palette.isDark { Pixel.fill(&ctx, bx + 1, top + 3, cell, palette.sun) }
    }

    /// A few glowing motes drifting across the sky.
    private func motes(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int, horizon: Int, frame: Int) {
        let count = 6
        for i in 0..<count {
            let speed = 1 + Int(Pixel.hash(i, 1) * 3)
            let drift = (frame / speed) % (cols + 6)
            let col = (Int(Pixel.hash(i, 2) * Double(cols)) + drift) % (cols + 6) - 3
            let bob = Int(2 * sin(Double(frame) / 6 + Double(i)))
            let row = Int(Pixel.hash(i, 3) * Double(horizon) * 0.7) + bob
            let twinkle = (frame / 3 + i) % 5 < 3
            Pixel.fill(&ctx, col, row, cell, palette.accent.opacity(twinkle ? 0.9 : 0.4))
        }
    }
}

// MARK: - Dissolution (rising, twinkling motes)

struct FantasyDissolution: DissolutionEffect {
    var duration: Double = 3.8
    func makeBody(_ ctx: DissolutionContext, onComplete: @escaping () -> Void) -> AnyView {
        AnyView(FantasyDissolutionView(ctx: ctx, duration: duration, onComplete: onComplete))
    }
}

private struct FantasyDissolutionView: View {
    let ctx: DissolutionContext
    let duration: Double
    let onComplete: () -> Void

    @State private var gone = false
    @State private var start: Date?
    private let cell: CGFloat = 7
    private static let count = 30

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
                        .animation(.easeIn(duration: duration * 0.55).delay(Double(i) * duration * 0.12), value: gone)
                }
            }
            .frame(maxWidth: .infinity)

            if !ctx.reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { tl in
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
        let gold = ctx.palette.sun
        let violet = ctx.palette.accent
        for i in 0..<Self.count {
            let delay = Pixel.hash(i, 7) * duration * 0.4
            let local = t - delay
            if local <= 0 { continue }
            let p = min(1.0, local / max(duration - delay, 0.001))

            let startX = Pixel.hash(i, 1) * Double(size.width)
            let startY = (0.34 + Pixel.hash(i, 2) * 0.34) * Double(size.height)
            let rise = p * Double(size.height) * 0.6
            let sway = sin(local * (0.9 + Pixel.hash(i, 3) * 1.4) + Pixel.hash(i, 4) * 6.28) * (16 + Pixel.hash(i, 5) * 24)

            let pcell = cell * (0.6 + Pixel.hash(i, 11) * 0.9)
            let qx = ((startX + sway) / Double(pcell)).rounded() * Double(pcell)
            let qy = ((startY - rise) / Double(pcell)).rounded() * Double(pcell)

            // Gentle twinkle plus a fade over the last third.
            let twinkle = 0.55 + 0.45 * sin(local * 6 + Double(i))
            let fade = p < 0.66 ? 1.0 : max(0, 1 - (p - 0.66) / 0.34)
            let opacity = twinkle * fade
            if opacity <= 0.03 { continue }

            let core = (i % 2 == 0 ? gold : violet)
            // A soft glow (faint orthogonal halo) around a bright core.
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                c.fill(Path(CGRect(x: qx + Double(dx) * Double(pcell), y: qy + Double(dy) * Double(pcell), width: pcell, height: pcell)),
                       with: .color(core.opacity(opacity * 0.22)))
            }
            c.fill(Path(CGRect(x: qx, y: qy, width: pcell, height: pcell)), with: .color(core.opacity(opacity)))
        }
    }
}
