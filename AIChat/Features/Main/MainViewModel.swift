import Foundation

/// Главный экран: показывает PRO только без подписки и обновляется сразу после покупки.
@MainActor
final class MainViewModel: ObservableObject {
    @Published private(set) var isPremium: Bool

    private let subscription: any SubscriptionService

    init(subscription: any SubscriptionService) {
        self.subscription = subscription
        isPremium = subscription.isPremium
    }

    var showsProButton: Bool { !isPremium }

    /// Живёт, пока экран на экране (`.task`).
    func observeSubscription() async {
        for await isPremium in subscription.premiumUpdates() {
            self.isPremium = isPremium
        }
    }
}
