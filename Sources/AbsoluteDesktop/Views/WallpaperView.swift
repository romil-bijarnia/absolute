import SwiftUI
import AbsoluteCore

struct WallpaperView: View {
    let wallpaper: Wallpaper

    private var colors: [Color] {
        switch wallpaper {
        case .ocean: return [Color(red: 0.03, green: 0.16, blue: 0.29), Color(red: 0.12, green: 0.45, blue: 0.65), Color(red: 0.28, green: 0.76, blue: 0.86)]
        case .dusk: return [Color(red: 0.13, green: 0.10, blue: 0.28), Color(red: 0.51, green: 0.25, blue: 0.49), Color(red: 0.95, green: 0.58, blue: 0.47)]
        case .forest: return [Color(red: 0.04, green: 0.17, blue: 0.18), Color(red: 0.13, green: 0.40, blue: 0.36), Color(red: 0.52, green: 0.71, blue: 0.48)]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(0..<6) { index in
                    let depth = CGFloat(index) / 6
                    Path { path in
                        path.move(to: CGPoint(x: -width * 0.1, y: height * (0.24 + depth * 0.63)))
                        path.addCurve(to: CGPoint(x: width * 1.1, y: height * (0.30 + depth * 0.62)),
                            control1: CGPoint(x: width * 0.20, y: height * (1.02 + depth * 0.12)),
                            control2: CGPoint(x: width * 0.72, y: height * (-0.20 + depth * 0.68)))
                        path.addLine(to: CGPoint(x: width * 1.1, y: height * 1.1))
                        path.addLine(to: CGPoint(x: -width * 0.1, y: height * 1.1))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [colors[2].opacity(0.16 + depth * 0.12), colors[0].opacity(0.60)],
                        startPoint: .topTrailing, endPoint: .bottomLeading))
                }
                RadialGradient(colors: [colors[2].opacity(0.32), .clear],
                    center: .topTrailing, startRadius: 10, endRadius: width * 0.8)
            }
        }
        .accessibilityHidden(true)
    }
}
