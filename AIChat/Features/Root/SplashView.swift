import SwiftUI

/// Сплэш на время открытия базы (макет «Splash»): маскот и полоса прогресса.
struct SplashView: View {
    private static let trackWidth: CGFloat = 212
    @State private var progress: CGFloat = 0.15

    var body: some View {
        VStack(spacing: 24) {
            Image("Mascot")
                .resizable()
                .scaledToFill()
                .frame(width: 143, height: 142)
                .accessibilityHidden(true)
            Capsule()
                .fill(Color.appFillTertiary)
                .frame(width: Self.trackWidth, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(AppGradient.primary)
                        .frame(width: Self.trackWidth * progress, height: 4)
                }
                .accessibilityLabel(Text("Loading"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 1)) { progress = 1 }
        }
    }
}

#if DEBUG
#Preview { SplashView() }
#endif
