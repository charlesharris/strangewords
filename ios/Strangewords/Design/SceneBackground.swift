import SwiftUI

/// The day/night scene behind everything: a soft sky gradient with a celestial
/// body placed by time of day (a low dawn sun, a high midday sun, or a moon and
/// stars at night). Deliberately quiet — it sets mood, it doesn't perform.
/// A richer, dynamic scene can replace this later.
struct SceneBackground: View {
    let palette: Palette
    let timeOfDay: TimeOfDay

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [palette.skyTop, palette.skyBottom],
                               startPoint: .top, endPoint: .bottom)

                if timeOfDay == .night {
                    Stars().opacity(0.7)
                }

                // Sun / moon — a soft glow, low at dawn, high by day/night.
                Circle()
                    .fill(palette.sun)
                    .frame(width: bodySize, height: bodySize)
                    .blur(radius: timeOfDay == .night ? 2 : 14)
                    .opacity(timeOfDay == .night ? 0.95 : 0.7)
                    .position(x: geo.size.width * bodyPos.x,
                              y: geo.size.height * bodyPos.y)
                    .overlay {
                        if timeOfDay == .night {
                            // A faint halo around the moon.
                            Circle()
                                .fill(palette.sun)
                                .frame(width: bodySize * 2.2, height: bodySize * 2.2)
                                .blur(radius: 30).opacity(0.12)
                                .position(x: geo.size.width * bodyPos.x,
                                          y: geo.size.height * bodyPos.y)
                        }
                    }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
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
        case .morning:   return (0.24, 0.32) // rising, low and to the side
        case .afternoon: return (0.78, 0.15) // high overhead
        case .night:     return (0.76, 0.16) // a moon up in the corner
        }
    }
}

/// A scattering of faint stars for the night scene. Positions are fixed so the
/// sky doesn't twinkle differently on every redraw.
private struct Stars: View {
    private static let points: [(CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.10, 1.6), (0.30, 0.06, 1.2), (0.46, 0.13, 1.8), (0.62, 0.05, 1.3),
        (0.88, 0.09, 1.5), (0.20, 0.22, 1.1), (0.55, 0.20, 1.4), (0.92, 0.24, 1.2),
        (0.08, 0.30, 1.3), (0.40, 0.30, 1.0), (0.70, 0.28, 1.6), (0.34, 0.40, 1.2),
        (0.84, 0.38, 1.1), (0.16, 0.44, 1.4),
    ]
    var body: some View {
        GeometryReader { geo in
            ForEach(Array(Self.points.enumerated()), id: \.offset) { _, p in
                Circle()
                    .fill(.white)
                    .frame(width: p.2, height: p.2)
                    .opacity(0.55)
                    .position(x: geo.size.width * p.0, y: geo.size.height * p.1)
            }
        }
    }
}
