import Testing
@testable import AIChat

@MainActor
struct MainViewModelTests {
    /// PRO — только без подписки и пропадает сразу после покупки, без перезапуска.
    @Test func proButtonFollowsSubscription() async throws {
        let subscription = FakeSubscriptionService(isPremium: false)
        let model = MainViewModel(subscription: subscription)
        #expect(model.showsProButton)
        let task = Task { await model.observeSubscription() }
        defer { task.cancel() }

        subscription.setPremium(true)

        try await waitUntil { !model.showsProButton }
    }

    @Test func premiumUserHasNoProButton() {
        #expect(!MainViewModel(subscription: FakeSubscriptionService(isPremium: true)).showsProButton)
    }
}
