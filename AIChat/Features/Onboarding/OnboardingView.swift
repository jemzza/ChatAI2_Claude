import SwiftUI

/// Онбординг из 2 экранов (макет «onboarding 1/2»): листается свайпом или «Continue»;
/// после второго — `onFinish` (дальше роутер показывает пейвол).
struct OnboardingView: View {
    struct Page: Identifiable {
        let id: Int
        let image: String
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
    }

    static let pages = [
        Page(id: 0, image: "OnboardingChat", title: "Ask AI anything",
             subtitle: "Answers, emails, ideas and plans in seconds"),
        Page(id: 1, image: "OnboardingVideo", title: "Turn photos into videos",
             subtitle: "Pick a template — AI animates your photo"),
    ]

    let onFinish: () -> Void
    @State private var selection = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                ForEach(Self.pages) { page in
                    pageView(page).tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 20) {
                PageIndicator(count: Self.pages.count, selection: selection)
                GradientButton(title: "Continue", action: next)
                    .padding(.horizontal, AppMetrics.sideInset)
            }
            .padding(.bottom, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 12) {
            Text(page.title)
                .font(AppFont.title)
                .foregroundStyle(Color.appAccent)
            Text(page.subtitle)
                .font(AppFont.body)
                .foregroundStyle(Color.appLabelTertiary)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, AppMetrics.sideInset)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Image(page.image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

    private func next() {
        if selection < Self.pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.35)) { selection += 1 }
        } else {
            onFinish()
        }
    }
}

/// Точки страниц: активная — градиентная «таблетка» 22×8, остальные — точки 8×8.
struct PageIndicator: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let isActive = index == selection
                Capsule()
                    .fill(isActive ? AnyShapeStyle(AppGradient.primary) : AnyShapeStyle(Color.white.opacity(0.25)))
                    .frame(width: isActive ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(selection + 1) of \(count)"))
    }
}

#if DEBUG
#Preview { OnboardingView {} }
#endif
