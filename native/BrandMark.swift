import SwiftUI

// The same seven glass spheres, spacing and lighting used by the desktop reveal.
struct ConstantMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<7, id: \.self) { index in
                    let angle = Double(max(0, index - 1)) * .pi / 3
                    Circle().fill(RadialGradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: Color(red: 0.74, green: 0.9, blue: 1), location: 0.32),
                        .init(color: Color(red: 0.16, green: 0.49, blue: 0.92), location: 0.72),
                        .init(color: Color(red: 0.025, green: 0.12, blue: 0.4), location: 1)
                    ], center: .init(x: 0.34, y: 0.23), startRadius: 0, endRadius: size * 44 / 154))
                        .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: max(0.3, size * 0.7 / 154)))
                        .frame(width: size * 44 / 154, height: size * 44 / 154)
                        .shadow(color: .blue.opacity(0.25), radius: size * 0.025)
                        .offset(x: index == 0 ? 0 : cos(angle) * size * 55 / 154,
                                y: index == 0 ? 0 : sin(angle) * size * 55 / 154)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.accessibilityHidden(true)
    }
}

struct ConstantAppIcon: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.17, blue: 0.34), Color(red: 0.015, green: 0.035, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: size * 0.2).stroke(.white.opacity(0.23), lineWidth: max(0.4, size * 0.002)))
                .frame(width: size * 0.88, height: size * 0.88)
                .shadow(color: .black.opacity(0.22), radius: size * 0.018, y: size * 0.012)
            Circle().fill(Color.blue.opacity(0.32)).frame(width: size * 0.53).blur(radius: size * 0.1)
            ConstantMark().frame(width: size * 0.66, height: size * 0.66)
        }.frame(width: size, height: size)
    }
}
