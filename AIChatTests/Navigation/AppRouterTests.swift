import Foundation
import Testing
@testable import AIChat

@MainActor
struct AppRouterTests {
    @Test func firstLaunchStartsWithOnboarding() {
        let router = AppRouter(settings: InMemorySettingsStore())
        #expect(router.stage == .onboarding)
        #expect(router.paywall == nil)
    }

    /// Онбординг → пейвол поверх главного; при следующем запуске — сразу главный.
    @Test func finishingOnboardingShowsPaywallOnceAndRemembers() {
        let settings = InMemorySettingsStore()
        let router = AppRouter(settings: settings)

        router.finishOnboarding()

        #expect(router.stage == .main)
        #expect(router.paywall?.source == .onboarding)
        #expect(settings.hasCompletedOnboarding)
        let relaunched = AppRouter(settings: settings)
        #expect(relaunched.stage == .main)
        #expect(relaunched.paywall == nil)
    }

    @Test func requirePremiumOpensPaywallOnlyForFreeUser() {
        let router = AppRouter(settings: InMemorySettingsStore(hasCompletedOnboarding: true))

        #expect(router.requirePremium(FakeSubscriptionService(isPremium: true)))
        #expect(router.paywall == nil)

        #expect(!router.requirePremium(FakeSubscriptionService(isPremium: false)))
        #expect(router.paywall?.source == .premiumAction)
    }

    @Test func paywallIsNotStackedTwice() {
        let router = AppRouter(settings: InMemorySettingsStore(hasCompletedOnboarding: true))
        router.showPaywall(from: .proButton)
        let first = router.paywall
        router.showPaywall(from: .settings)
        #expect(router.paywall == first)
        router.dismissPaywall()
        #expect(router.paywall == nil)
    }

    @Test func stackOperations() {
        let router = AppRouter(settings: InMemorySettingsStore(hasCompletedOnboarding: true))
        let id = UUID()
        router.push(.templates)
        router.push(.templatePreview(templateId: 7))
        router.replaceTop(with: .generation(id: id))
        #expect(router.path == [.templates, .generation(id: id)])
        router.pop()
        #expect(router.path == [.templates])
        router.push(.settings)
        router.popToRoot()
        #expect(router.path.isEmpty)
    }
}
