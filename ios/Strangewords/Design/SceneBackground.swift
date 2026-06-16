import SwiftUI

/// The day/night scene behind everything: a layered, procedural landscape that
/// shifts with the time of day. Distant ridges, a soft foreground hill, the
/// celestial body, stars or drifting clouds, and a cherry branch — all tinted
/// by the palette and kept quiet so the poem stays the center (brief.v4.md §8).
/// All drawn in code: crisp at any size, no assets. Motion respects Reduce Motion.
struct SceneBackground: View {
    let palette: Palette
    let timeOfDay: TimeOfDay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    @State private var twinkle = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(colors: [palette.skyTop, palette.skyBottom],
                               startPoint: .top, endPoint: .bottom)

                // Sky life: stars at night, soft clouds by day.
                if timeOfDay == .night {
                    Stars(color: .white)
                        .opacity(twinkle ? 0.75 : 0.5)
                } else {
                    clouds(w: w, h: h)
                }

                celestial(w: w, h: h)

                // Distant ridge, then a closer hill — the horizon.
                HillShape(baseline: 0.66, amplitude: 16, wavelength: w * 0.9, phase: 0.6)
                    .fill(palette.far)
                    .opacity(0.9)
                HillShape(baseline: 0.82, amplitude: 26, wavelength: w * 0.7, phase: 2.2)
                    .fill(palette.near)

                CherryBranch(branch: palette.ink.opacity(0.28), blossom: palette.accent)
                    .frame(width: w * 0.6, height: h * 0.34)
                    .position(x: w * 0.74, y: h * 0.14)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 80).repeatForever(autoreverses: true)) { drift = true }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { twinkle = true }
        }
    }

    // MARK: - Celestial body

    @ViewBuilder
    private func celestial(w: CGFloat, h: CGFloat) -> some View {
        let pos = bodyPos
        ZStack {
            if timeOfDay == .night {
                Circle().fill(palette.sun)
                    .frame(width: bodySize * 2.4, height: bodySize * 2.4)
                    .blur(radius: 34).opacity(0.14)
            }
            Circle().fill(palette.sun)
                .frame(width: bodySize, height: bodySize)
                .blur(radius: timeOfDay == .night ? 1.5 : 16)
                .opacity(timeOfDay == .night ? 0.95 : 0.7)
        }
        .position(x: w * pos.x, y: h * pos.y)
    }

    private var bodySize: CGFloat {
        switch timeOfDay {
        case .morning: return 150
        case .afternoon: return 110
        case .night: return 72
        }
    }
    private var bodyPos: (x: CGFloat, y: CGFloat) {
        switch timeOfDay {
        case .morning:   return (0.24, 0.30)
        case .afternoon: return (0.78, 0.14)
        case .night:     return (0.74, 0.13)
        }
    }

    // MARK: - Clouds (day)

    @ViewBuilder
    private func clouds(w: CGFloat, h: CGFloat) -> some View {
        let shift = drift ? w * 0.06 : -w * 0.06
        ZStack {
            cloud(width: 150).position(x: w * 0.30, y: h * 0.20).offset(x: shift)
            cloud(width: 110).position(x: w * 0.70, y: h * 0.30).offset(x: -shift)
            cloud(width: 90).position(x: w * 0.52, y: h * 0.12).offset(x: shift * 0.6)
        }
        .opacity(0.5)
    }

    private func cloud(width: CGFloat) -> some View {
        Capsule()
            .fill(.white)
            .frame(width: width, height: width * 0.32)
            .blur(radius: 18)
    }
}

// MARK: - Hills

/// A smooth ridge silhouette: a sampled sine curve closed to the bottom edge.
private struct HillShape: Shape {
    var baseline: CGFloat   // fraction of height for the ridge midline
    var amplitude: CGFloat  // points
    var wavelength: CGFloat // points per cycle
    var phase: CGFloat      // radians

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let mid = h * baseline
        p.move(to: CGPoint(x: 0, y: h))
        var x: CGFloat = 0
        let step: CGFloat = 6
        while x <= w {
            let y = mid + amplitude * sin(phase + (x / max(wavelength, 1)) * 2 * .pi)
            p.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }
}

// MARK: - Cherry branch

/// A spare branch arcing in from a corner with a few blossoms — the boards'
/// recurring motif, drawn small and quiet.
private struct CherryBranch: View {
    let branch: Color
    let blossom: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w, y: h * 0.08))
                    p.addQuadCurve(to: CGPoint(x: w * 0.18, y: h * 0.62),
                                   control: CGPoint(x: w * 0.62, y: h * 0.18))
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.38))
                    p.addQuadCurve(to: CGPoint(x: w * 0.34, y: h * 0.16),
                                   control: CGPoint(x: w * 0.46, y: h * 0.22))
                }
                .stroke(branch, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                ForEach(Array(blossoms.enumerated()), id: \.offset) { _, b in
                    Blossom(color: blossom)
                        .frame(width: b.size, height: b.size)
                        .position(x: w * b.x, y: h * b.y)
                }
            }
        }
    }

    private var blossoms: [(x: CGFloat, y: CGFloat, size: CGFloat)] {
        [(0.18, 0.62, 13), (0.30, 0.50, 10), (0.42, 0.40, 12),
         (0.34, 0.16, 11), (0.58, 0.30, 9), (0.86, 0.14, 12)]
    }
}

/// A tiny five-petal blossom: overlapping soft circles with a lighter heart.
private struct Blossom: View {
    let color: Color
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .offset(y: -4)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(color.opacity(0.5)).frame(width: 4, height: 4)
        }
        .opacity(0.85)
    }
}

/// A scattering of faint stars for the night scene. Fixed positions so the sky
/// doesn't rearrange on every redraw.
private struct Stars: View {
    let color: Color
    private static let points: [(CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.10, 1.6), (0.30, 0.06, 1.2), (0.46, 0.13, 1.8), (0.62, 0.05, 1.3),
        (0.88, 0.09, 1.5), (0.20, 0.22, 1.1), (0.55, 0.20, 1.4), (0.92, 0.24, 1.2),
        (0.08, 0.30, 1.3), (0.40, 0.30, 1.0), (0.70, 0.27, 1.6), (0.34, 0.40, 1.2),
        (0.84, 0.37, 1.1), (0.16, 0.45, 1.4), (0.50, 0.44, 1.0),
    ]
    var body: some View {
        GeometryReader { geo in
            ForEach(Array(Self.points.enumerated()), id: \.offset) { _, p in
                Circle().fill(color).frame(width: p.2, height: p.2)
                    .position(x: geo.size.width * p.0, y: geo.size.height * p.1)
            }
        }
    }
}
