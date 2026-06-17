import SwiftUI
import UIKit

/// Shared low-level pixel-drawing helpers used by the themed scenes
/// (`NatureScene`, `SciFiScene`, `FantasyScene`). Everything is drawn on a
/// coarse cell grid via `Canvas`, so scenes stay crisp at any size with no
/// assets. A scene composes these primitives plus its own unique elements.
enum Pixel {
    /// Pixel (cell) size in points for a given width and target column count.
    static func cellSize(width: CGFloat, columns: CGFloat) -> CGFloat {
        max(2, (width / columns).rounded())
    }

    /// Fill one cell.
    static func fill(_ ctx: inout GraphicsContext, _ col: Int, _ row: Int, _ cell: CGFloat, _ color: Color) {
        ctx.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(color))
    }

    private static let bayer: [[Int]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

    /// A dithered vertical gradient from `top` to `bottom` over rows `0..<horizon`,
    /// quantized into `bands` colors and smoothed with Bayer ordered dithering.
    static func sky(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, horizon: Int, top: Color, bottom: Color, bands: Int = 5) {
        let colors = (0..<bands).map { top.mix(bottom, Double($0) / Double(bands - 1)) }
        for row in 0..<max(horizon, 1) {
            let g = Double(row) / Double(max(horizon - 1, 1)) * Double(bands - 1)
            let low = Int(g.rounded(.down))
            let frac = g - Double(low)
            for col in 0..<cols {
                let threshold = (Double(bayer[col & 3][row & 3]) + 0.5) / 16.0
                let idx = frac > threshold ? min(low + 1, bands - 1) : low
                fill(&ctx, col, row, cell, colors[idx])
            }
        }
    }

    /// A filled pixel disc.
    static func disc(_ ctx: inout GraphicsContext, cx: Int, cy: Int, rad: Int, cell: CGFloat, _ color: Color) {
        for dy in -rad...rad {
            for dx in -rad...rad where dx * dx + dy * dy <= rad * rad {
                fill(&ctx, cx + dx, cy + dy, cell, color)
            }
        }
    }

    /// A one-cell-thick ring between radii `inner` and `outer`.
    static func ring(_ ctx: inout GraphicsContext, cx: Int, cy: Int, inner: Int, outer: Int, cell: CGFloat, _ color: Color) {
        for dy in -outer...outer {
            for dx in -outer...outer {
                let d = dx * dx + dy * dy
                if d > inner * inner && d <= outer * outer {
                    fill(&ctx, cx + dx, cy + dy, cell, color)
                }
            }
        }
    }

    /// A stepped silhouette (hills / ridge): a quantized sine filled down to `rows`.
    static func ridge(_ ctx: inout GraphicsContext, cols: Int, rows: Int, cell: CGFloat, baseRow: Int, amp: Double, wavelength: Double, phase: Double, _ color: Color) {
        for col in 0..<cols {
            let y = baseRow + Int((amp * sin(Double(col) / max(wavelength, 0.001) + phase)).rounded())
            if y < rows {
                for row in max(0, y)..<rows { fill(&ctx, col, row, cell, color) }
            }
        }
    }

    /// A field of twinkling points above `maxRow`.
    static func stars(_ ctx: inout GraphicsContext, cell: CGFloat, cols: Int, maxRow: Int, count: Int, frame: Int, bright: Color, dim: Color) {
        for i in 0..<count {
            let col = Int(hash(i, 1) * Double(cols))
            let row = Int(hash(i, 2) * Double(maxRow))
            let phase = (frame / 2 + i) % 7
            fill(&ctx, col, row, cell, phase < 2 ? bright : dim)
        }
    }

    /// Deterministic [0,1) hash so placements are stable across redraws.
    static func hash(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - floor(x)
    }
}

// MARK: - Palette colour mixing (shared by scenes and dissolutions)

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
