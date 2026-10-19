import SwiftUI

/// Корень после загрузки: онбординг или главный экран со стеком навигации,
/// пейвол — поверх всего (`fullScreenCover`).
struct RootView: View {
    let dependencies: AppDependencies
    @StateObject private var router: AppRouter

    init(dependencies: AppDependencies, settings: any SettingsStoring) {
        self.dependencies = dependencies
        _router = StateObject(wrappedValue: AppRouter(settings: settings))
    }

    var body: some View {
        ZStack {
            switch router.stage {
            case .onboarding:
                OnboardingView { router.finishOnboarding() }
                    .transition(.opacity)
            case .main:
                NavigationStack(path: $router.path) {
                    MainView(subscription: dependencies.subscription)
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(route)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: router.stage)
        .fullScreenCover(item: $router.paywall) { _ in
            PaywallView(subscription: dependencies.subscription) {
                router.dismissPaywall()
            }
        }
        .environmentObject(router)
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case let .chat(chatId, prompt):
            ChatView(chatId: chatId, prompt: prompt, dependencies: dependencies)
        case .templates:
            TemplatesView(dependencies: dependencies)
        case let .templatePreview(templateId, category):
            TemplatePreviewView(templateId: templateId, category: category, dependencies: dependencies)
        case let .generation(id):
            GenerationView(id: id, dependencies: dependencies)
        case .history:
            PlaceholderScreen(title: "History", showsBack: true)
        case .settings:
            PlaceholderScreen(title: "Settings", showsBack: true)
        }
    }
}

/// Временный экран, пока настоящий не сделан (разделы 6.x плана).
struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var showsBack = false
    var action: () -> Void = {}
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 24) {
            if showsBack {
                NavigationHeader(title) { router.pop() }
            }
            Spacer()
            Text(title)
                .font(AppFont.title)
                .foregroundStyle(Color.appAccent)
                .multilineTextAlignment(.center)
            if let actionTitle {
                GradientButton(title: actionTitle, action: action)
                    .padding(.horizontal, AppMetrics.sideInset)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }
}
