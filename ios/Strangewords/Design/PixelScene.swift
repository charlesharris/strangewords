import SwiftUI
import UIKit

/// A procedural **pixel-art** day/night scene, drawn entirely in code on a
/// coarse grid so it reads as crisp pixels at any screen size — no assets. It
/// shifts with the local time of day (morning / afternoon / night, chosen by
/// `TimeOfDay`) and animates quietly: clouds drift by day, stars twinkle by
/// night, all in whole-pixel steps for an authentic retro feel. Colors are
/// pulled from the same `Palette` as the rest of the app, so the poem stays
/// legible and the theming stays coherent. Motion respects Reduce Motion.
struct PixelScene: View {
    let palette: Palette
    let timeOfDay: TimeOfDay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Roughly how many pixels span the width. Lower = chunkier. [TUNABLE]
    private let columns: CGFloat = 64
    /// Animation step rate (frames/sec) — deliberately low for the pixel look.
    private let fps: Double = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                let frame = reduceMotion ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate * fps)
                Painter(palette: palette, timeOfDay: timeOfDay, columns: columns)
                    .draw(into: &ctx, size: size, frame: frame)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - The painter

/// Stateless drawing logic, kept apart from the View so it's easy to reason
/// about and to evolve scene by scene.
private struct Painter {
    let palette: Palette
    let timeOfDay: TimeOfDay
    let columns: CGFloat

    func draw(into ctx: inout GraphicsContext, size: CGSize, frame: Int) {
        let cell = (size.width / columns).rounded()
        let cols = Int((size.width / cell).rounded(.up))
        let rows = Int((size.height / cell).rounded(.up))

        // The two horizons, in rows from the top.
        let farHorizon = Int(Double(rows) * 0.62)
        let nearHorizon = Int(Double(rows) * 0.74)

        sky(&ctx, cell: cell, cols: cols, rows: rows, horizon: farHorizon)

        switch timeOfDay {
        case .night:
            stars(&ctx, cell: cell, cols: cols, horizon: farHorizon, frame: frame)
            celestial(&ctx, cell: cell, cols: cols, rows: rows)
        default:
            celestial(&ctx, cell: cell, cols: cols, rows: rows)
            clouds(&ctx, cell: cell, cols: cols, horizon: farHorizon, frame: frame)
        }

        hills(&ctx, cell: cell, cols: cols, rows: rows, farHorizon: farHorizon, nearHorizon: nearHorizon)
    }

    // MARK: Sky — a limited palette of bands, smoothed with Bayer ordered
    // dithering so the gradient reads as classic pixel-art stippling rather than
    // hard steps or dashed lines.

    private static let bayer4: [[Int]] = [
        [0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5],
    ]

    private func sky(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int, horizon: Int) {
        let bands = 5
        // Precompute the band colors once.
        let colors = (0..<bands).map { palette.skyTop.mix(palette.skyBottom, Double($0) / Double(bands - 1)) }
        for row in 0..<horizon {
            let g = Double(row) / Double(max(horizon - 1, 1)) * Double(bands - 1)
            let low = Int(g.rounded(.down))
            let frac = g - Double(low)
            for col in 0..<cols {
                let threshold = (Double(Self.bayer4[col & 3][row & 3]) + 0.5) / 16.0
                let idx = frac > threshold ? min(low + 1, bands - 1) : low
                px(&ctx, col, row, cell: cell, color: colors[idx])
            }
        }
    }

    // MARK: Celestial body — a pixel disc (sun by day, moon at night)

    private func celestial(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int) {
        let (fx, fy, rad): (Double, Double, Int)
        switch timeOfDay {
        case .morning:   (fx, fy, rad) = (0.24, 0.28, 6)
        case .afternoon: (fx, fy, rad) = (0.76, 0.16, 5)
        case .night:     (fx, fy, rad) = (0.74, 0.16, 5)
        }
        let cx = Int(Double(cols) * fx)
        let cy = Int(Double(rows) * fy)
        if timeOfDay == .night {
            moon(&ctx, cx: cx, cy: cy, rad: rad, cell: cell)
        } else {
            sun(&ctx, cx: cx, cy: cy, rad: rad, cell: cell)
        }
    }

    private func sun(_ ctx: inout GraphicsContext, cx: Int, cy: Int, rad: Int, cell: CGFloat) {
        let body = palette.sun
        ring(&ctx, cx: cx, cy: cy, inner: rad, outer: rad + 1, cell: cell, color: body.opacity(0.28))
        disc(&ctx, cx: cx, cy: cy, rad: rad, cell: cell, color: body)
    }

    /// A richer moon: a soft layered glow, gentle surface shading so it reads as
    /// a sphere lit from the upper-left, and a scatter of craters.
    private func moon(_ ctx: inout GraphicsContext, cx: Int, cy: Int, rad: Int, cell: CGFloat) {
        let body = palette.sun
        // Layered glow, fading outward.
        ring(&ctx, cx: cx, cy: cy, inner: rad, outer: rad + 1, cell: cell, color: body.opacity(0.18))
        ring(&ctx, cx: cx, cy: cy, inner: rad + 1, outer: rad + 2, cell: cell, color: body.opacity(0.10))
        ring(&ctx, cx: cx, cy: cy, inner: rad + 2, outer: rad + 3, cell: cell, color: body.opacity(0.05))

        // Disc with a shaded terminator on the lower-right (lit from upper-left).
        let shade = body.mix(palette.skyTop, 0.30)
        let edge = body.mix(palette.skyTop, 0.15)
        let term = Int(Double(rad) * 0.7)
        for dy in -rad...rad {
            for dx in -rad...rad where dx * dx + dy * dy <= rad * rad {
                let d = dx * dx + dy * dy
                let color: Color
                if dx + dy > term + 1 { color = shade }
                else if dx + dy > term { color = edge }
                else if d > (rad - 1) * (rad - 1) { color = edge } // soften the rim
                else { color = body }
                px(&ctx, cx + dx, cy + dy, cell: cell, color: color)
            }
        }

        // Craters of varied size.
        let crater = body.mix(palette.skyTop, 0.50)
        let craters: [(Int, Int, Int)] = [(-2, -1, 1), (1, 1, 1), (2, -2, 0), (-1, 2, 0), (-3, 1, 0)]
        for (ox, oy, r) in craters {
            for dy in -r...r {
                for dx in -r...r where dx * dx + dy * dy <= r * r {
                    px(&ctx, cx + ox + dx, cy + oy + dy, cell: cell, color: crater)
                }
            }
        }
    }

    private func disc(_ ctx: inout GraphicsContext, cx: Int, cy: Int, rad: Int, cell: CGFloat, color: Color) {
        for dy in -rad...rad {
            for dx in -rad...rad where dx * dx + dy * dy <= rad * rad {
                px(&ctx, cx + dx, cy + dy, cell: cell, color: color)
            }
        }
    }

    private func ring(_ ctx: inout GraphicsContext, cx: Int, cy: Int, inner: Int, outer: Int, cell: CGFloat, color: Color) {
        for dy in -outer...outer {
            for dx in -outer...outer {
                let d = dx * dx + dy * dy
                if d > inner * inner && d <= outer * outer {
                    px(&ctx, cx + dx, cy + dy, cell: cell, color: color)
                }
            }
        }
    }

    // MARK: Stars (night)

    private func stars(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, horizon: Int, frame: Int) {
        let count = 26
        for i in 0..<count {
            let col = Int(hash(i, 1) * Double(cols))
            let row = Int(hash(i, 2) * Double(horizon) * 0.85)
            // Twinkle: each star brightens on its own slow cycle.
            let phase = (frame / 2 + i) % 7
            let bright = phase < 2
            let c = bright ? Color.white : palette.sun.opacity(0.55)
            px(&ctx, col, row, cell: cell, color: c)
        }
    }

    // MARK: Clouds (day) — blocky blobs drifting and wrapping

    private func clouds(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, horizon: Int, frame: Int) {
        // Each cloud: base column, row, and a small mask of cells. Kept well
        // above the ridge so they never collide with the horizon.
        let clouds: [(col: Int, row: Int, speed: Int)] = [
            (8, Int(Double(horizon) * 0.22), 3),
            (40, Int(Double(horizon) * 0.12), 4),
            (26, Int(Double(horizon) * 0.34), 2),
        ]
        let mask = [(0, 0), (1, 0), (2, 0), (3, 0), (1, -1), (2, -1), (-1, 0), (0, 1), (1, 1), (2, 1)]
        let white = Color.white.opacity(0.55)
        for (idx, cloud) in clouds.enumerated() {
            let drift = (frame / cloud.speed) % (cols + 8)
            let baseCol = (cloud.col + drift) % (cols + 8) - 4
            for (dx, dy) in mask {
                px(&ctx, baseCol + dx, cloud.row + dy, cell: cell, color: white)
                _ = idx
            }
        }
    }

    // MARK: Hills — stepped pixel silhouettes

    private func hills(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, rows: Int, farHorizon: Int, nearHorizon: Int) {
        for col in 0..<cols {
            // Far ridge: a gentle quantized sine.
            let farY = farHorizon + Int(round(2.0 * sin(Double(col) / 7.0 + 0.6)))
            for row in farY..<rows {
                px(&ctx, col, row, cell: cell, color: palette.far)
            }
            // Near hill, drawn on top: lower and a touch rounder.
            let nearY = nearHorizon + Int(round(2.5 * sin(Double(col) / 5.0 + 2.2)))
            for row in nearY..<rows {
                px(&ctx, col, row, cell: cell, color: palette.near)
            }
        }
    }

    // MARK: - Cell helpers

    private func px(_ ctx: inout GraphicsContext, _ col: Int, _ row: Int, cell: CGFloat, color: Color) {
        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
        ctx.fill(Path(rect), with: .color(color))
    }

    /// Deterministic [0,1) hash so star/cloud placement is stable across redraws.
    private func hash(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - floor(x)
    }
}

// MARK: - Palette colour mixing

extension Color {
    /// Linear blend toward another color (`f` 0→self, 1→other), in sRGB.
    func mix(_ other: Color, _ f: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(max(0, min(1, f)))
        return Color(.sRGB, red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: 1)
    }
}
