import SwiftUI

/// Фоновое свечение сверху экрана (пейвол, главный): размытый эллипс фирменного градиента,
/// форму которому задают два размытых эллипса цвета фона. Координаты — из макета (ширина 390),
/// масштабируются по ширине экрана.
struct GlowBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 390
            ZStack(alignment: .topLeading) {
                Color.appBackground
                Ellipse()
                    .fill(AppGradient.primary)
                    .frame(width: 619 * scale, height: 246 * scale)
                    .rotationEffect(.degrees(18.36))
                    .opacity(0.5)
                    .position(x: 254.6 * scale, y: 83.4 * scale)
                    .blur(radius: 50 * scale)
                Ellipse()
                    .fill(Color.appBackground)
                    .frame(width: 380 * scale, height: 232 * scale)
                    .position(x: 172.9 * scale, y: 215.1 * scale)
                    .blur(radius: 54 * scale)
                Ellipse()
                    .fill(Color.appBackground)
                    .frame(width: 312 * scale, height: 232 * scale)
                    .position(x: 473.6 * scale, y: 265.1 * scale)
                    .blur(radius: 54 * scale)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview { GlowBackground() }
#endif
