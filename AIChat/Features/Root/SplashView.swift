import SwiftUI

/// Сплэш на время открытия базы: маскот и полоса прогресса (макет «Splash»).
struct SplashView: View {
    @State private var progress: CGFloat = 0.1

    var body: some View {
        VStack(spacing: 40) {
            Image("Mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Capsule()
                .fill(Color.appFillTertiary)
                .frame(width: 174, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(AppGradient.primary)
                        .frame(width: 174 * progress, height: 3)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { progress = 0.9 }
        }
    }
}

#if DEBUG
#Preview { SplashView() }
#endif
