import SwiftUI

// MARK: - The swappable seam

/// Everything a dissolution effect needs: the finished poem and the scene it
/// lives in.
struct DissolutionContext {
    let lines: [String]
    let palette: Palette
    let timeOfDay: TimeOfDay
    let reduceMotion: Bool
}

/// A dissolution effect renders the finished poem and animates its
/// disappearance — the app's emotional climax, the moment of letting go
/// (brief.v4.md §8). Effects are interchangeable so the *feel* of dissolution
/// can evolve: add a new type, conform it here, and point `Dissolutions.current`
/// at it. The reveal flow never changes.
protocol DissolutionEffect {
    /// How long the effect runs before the poem is gone (seconds).
    var duration: Double { get }
    /// A view that shows `ctx.lines` settled, then animates them away, calling
    /// `onComplete` exactly once when nothing remains.
    func makeBody(_ ctx: DissolutionContext, onComplete: @escaping () -> Void) -> AnyView
}

// The active dissolution is chosen by the current `SceneTheme` (see
// `SceneTheme.dissolution`); each theme bundles its own. The effects below are
// the conformers a theme can pick from.

// MARK: - Petal dissolution

/// The default: the poem rises and fades while a scatter of cherry petals
/// detaches and drifts down across the words, carrying them away. Under Reduce
/// Motion it becomes a still, slow fade.
struct PetalDissolution: DissolutionEffect {
    var duration: Double = 3.6
    func makeBody(_ ctx: DissolutionContext, onComplete: @escaping () -> Void) -> AnyView {
        AnyView(PetalDissolutionView(ctx: ctx, duration: duration, onComplete: onComplete))
    }
}

private struct PetalDissolutionView: View {
    let ctx: DissolutionContext
    let duration: Double
    let onComplete: () -> Void

    @State private var gone = false

    var body: some View {
        ZStack {
            // The poem itself, drifting upward and fading line by line.
            VStack(spacing: 18) {
                ForEach(Array(ctx.lines.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(Theme.poem())
                        .foregroundStyle(ctx.palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(gone ? 0 : 1)
                        .offset(y: lift(i))
                        .blur(radius: gone && !ctx.reduceMotion ? 5 : 0)
                        .animation(lineAnimation(i), value: gone)
                }
            }
            .frame(maxWidth: .infinity)

            // The petals — the motion layer, skipped under Reduce Motion.
            if !ctx.reduceMotion {
                PetalFall(color: ctx.palette.accent, gone: gone, duration: duration)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation { gone = true }   // per-element animations carry the timing
        }
        .task {
            try? await Task.sleep(for: .seconds(duration))
            onComplete()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The poem is dissolving.")
    }

    private func lift(_ i: Int) -> CGFloat {
        guard gone, !ctx.reduceMotion else { return 0 }
        return -28 - CGFloat(i) * 4
    }

    /// Lines leave top-first, gently staggered, so the poem reads as lifting away.
    private func lineAnimation(_ i: Int) -> Animation {
        if ctx.reduceMotion {
            return .easeInOut(duration: duration * 0.8)
        }
        let stagger = Double(i) * (duration * 0.10)
        return .easeIn(duration: duration * 0.65).delay(stagger)
    }
}

// MARK: - Falling petals

private struct PetalFall: View {
    let color: Color
    let gone: Bool
    let duration: Double

    private static let count = 16

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<Self.count, id: \.self) { i in
                let s = spec(i)
                PetalShape()
                    .fill(color.opacity(gone ? 0 : s.opacity))
                    .frame(width: s.size, height: s.size * 1.15)
                    .rotationEffect(.degrees(gone ? s.spin : s.spin * 0.2))
                    .position(
                        x: geo.size.width * s.x + (gone ? s.drift : 0),
                        y: geo.size.height * (gone ? s.endY : s.startY)
                    )
                    .animation(.easeIn(duration: duration).delay(s.delay), value: gone)
            }
        }
    }

    private struct Spec {
        let x, startY, endY: CGFloat
        let drift, size: CGFloat
        let spin, delay, opacity: Double
    }

    /// Deterministic per-petal parameters (hashed from the index), so the petals
    /// don't rearrange on every redraw.
    private func spec(_ i: Int) -> Spec {
        func r(_ salt: Int) -> Double {
            let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
            return x - floor(x)
        }
        return Spec(
            x: CGFloat(r(1)),
            startY: CGFloat(r(2) * 0.55),
            endY: 1.08 + CGFloat(r(3) * 0.12),
            drift: CGFloat((r(4) - 0.5) * 140),
            size: 9 + CGFloat(r(5) * 9),
            spin: (r(6) - 0.5) * 420,
            delay: r(7) * duration * 0.35,
            opacity: 0.55 + r(8) * 0.4
        )
    }
}

/// A single soft cherry petal: an oval narrowing to a point at the top with a
/// gentle notch at the base.
struct PetalShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.6), control: CGPoint(x: w, y: h * 0.08))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.86), control: CGPoint(x: w * 0.78, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.6), control: CGPoint(x: w * 0.22, y: h))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0), control: CGPoint(x: 0, y: h * 0.08))
        return p
    }
}

// MARK: - Pixel petal dissolution

/// The pixel-art counterpart to `PetalDissolution`, matching the `PixelScene`
/// backdrop: the poem fades line by line while a fall of blocky cherry petals
/// drifts down in whole-pixel steps, swaying as they go. At night the petals
/// lean pinker/purpler. Reduce Motion drops the fall and keeps only the fade.
struct PixelPetalDissolution: DissolutionEffect {
    var duration: Double = 3.8
    func makeBody(_ ctx: DissolutionContext, onComplete: @escaping () -> Void) -> AnyView {
        AnyView(PixelPetalDissolutionView(ctx: ctx, duration: duration, onComplete: onComplete))
    }
}

private struct PixelPetalDissolutionView: View {
    let ctx: DissolutionContext
    let duration: Double
    let onComplete: () -> Void

    @State private var gone = false
    @State private var start: Date?

    /// Pixel size of a petal cell, and how many petals fall.
    private let cell: CGFloat = 8
    private static let count = 24

    /// Hand-drawn petal frames. Cycling them flips the petal without ever
    /// rotating a sprite (which would blur). The sequence reads edge-on →
    /// three-quarter → full → three-quarter, so a petal looks like it's turning
    /// over as it falls. The shapes are rounded blobs (not plus/cross arms) so
    /// they read as blossoms. `true` marks the lighter heart cell.
    private static let frames: [[(x: Int, y: Int, heart: Bool)]] = [
        [(0, 0, true), (0, 1, false)],                                  // edge-on: a short pair
        [(0, 0, true), (1, 0, false), (0, 1, false)],                   // three-quarter: a rounded corner
        [(0, 0, true), (1, 0, false), (0, 1, false), (1, 1, false)],    // full: a rounded 2×2 blob
        [(1, 0, false), (0, 1, true), (1, 1, false)],                   // three-quarter (other side)
    ]

    var body: some View {
        ZStack {
            // The poem, fading top-first.
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

            // The falling pixel petals — the motion layer.
            if !ctx.reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { tl in
                    Canvas { c, size in
                        let t = start.map { tl.date.timeIntervalSince($0) } ?? 0
                        drawPetals(&c, size: size, t: t)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            start = Date()
            withAnimation { gone = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(duration))
            onComplete()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The poem is dissolving.")
    }

    private func drawPetals(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        // Two petal tints. At night they lean pinker / purpler than the base
        // accent; by day they stay the palette's accent rose.
        let night = ctx.timeOfDay == .night
        let tintPink = night ? ctx.palette.accent.mix(Color(0xE48FC6), 0.5) : ctx.palette.accent
        let tintPurple = night ? ctx.palette.accent.mix(Color(0x9B7BD8), 0.5) : ctx.palette.accent

        for i in 0..<Self.count {
            let delay = hash(i, 7) * duration * 0.3
            let local = t - delay
            if local <= 0 { continue }
            let p = min(1.0, local / max(duration - delay, 0.001))

            // Per-petal pixel size — same sprite, different scale, so the petals
            // vary from small to large (a sense of depth).
            let pcell = cell * (0.6 + hash(i, 11) * 0.9)   // ~5–12 pt

            let startX = hash(i, 1) * Double(size.width)
            let startY = (0.16 + hash(i, 2) * 0.40) * Double(size.height)
            let fall = p * Double(size.height) * 1.15

            // A lazy S-curve: two sines combine into an organic side-to-side
            // path, so the petals catch the air instead of dropping straight.
            let phase = hash(i, 4) * 6.28
            let freq = 0.8 + hash(i, 3) * 0.8
            let amp = 18 + hash(i, 5) * 22
            let sway = sin(local * freq + phase) * amp
                     + sin(local * freq * 0.5 + phase) * (amp * 0.4)

            // Quantize to this petal's pixel grid so the motion reads as pixel art.
            let qx = ((startX + sway) / Double(pcell)).rounded() * Double(pcell)
            let qy = ((startY + fall) / Double(pcell)).rounded() * Double(pcell)

            // Hold, then fade over the last 40% of the petal's life.
            let fade = p < 0.6 ? 1.0 : max(0, 1 - (p - 0.6) / 0.4)
            let opacity = (0.6 + hash(i, 6) * 0.4) * fade
            if opacity <= 0.01 { continue }

            // Flip-flutter: step through the frames at the petal's own rate and
            // direction, so it turns over as it falls.
            let fps = 2.5 + hash(i, 8) * 3.0
            let dir = hash(i, 9) < 0.5 ? 1 : -1
            var fi = (Int(local * fps) * dir + Int(hash(i, 10) * Double(Self.frames.count))) % Self.frames.count
            if fi < 0 { fi += Self.frames.count }
            let frame = Self.frames[fi]

            let body = (i % 2 == 0) ? tintPink : tintPurple
            let heart = ctx.palette.sun.mix(body, 0.5)

            for cellSpec in frame {
                let color = (cellSpec.heart ? heart : body).opacity(opacity)
                let rect = CGRect(x: CGFloat(qx) + CGFloat(cellSpec.x) * pcell,
                                  y: CGFloat(qy) + CGFloat(cellSpec.y) * pcell,
                                  width: pcell, height: pcell)
                c.fill(Path(rect), with: .color(color))
            }
        }
    }

    private func hash(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - floor(x)
    }
}

// MARK: - Fade dissolution (minimal alternate)

/// A quiet alternate with no particles: the poem simply fades and settles. Kept
/// as a second conformer to demonstrate the seam — set `Dissolutions.current`
/// to `FadeDissolution()` to use it.
struct FadeDissolution: DissolutionEffect {
    var duration: Double = 2.6
    func makeBody(_ ctx: DissolutionContext, onComplete: @escaping () -> Void) -> AnyView {
        AnyView(FadeDissolutionView(ctx: ctx, duration: duration, onComplete: onComplete))
    }
}

private struct FadeDissolutionView: View {
    let ctx: DissolutionContext
    let duration: Double
    let onComplete: () -> Void
    @State private var gone = false

    var body: some View {
        VStack(spacing: 18) {
            ForEach(Array(ctx.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.poem())
                    .foregroundStyle(ctx.palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(gone ? 0 : 1)
        .scaleEffect(gone && !ctx.reduceMotion ? 1.04 : 1)
        .onAppear { withAnimation(.easeInOut(duration: duration * 0.9)) { gone = true } }
        .task {
            try? await Task.sleep(for: .seconds(duration))
            onComplete()
        }
        .accessibilityLabel("The poem is dissolving.")
    }
}
