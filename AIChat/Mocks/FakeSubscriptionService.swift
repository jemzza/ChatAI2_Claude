#if DEBUG
import Foundation

/// Подписка, которой управляют вручную: `setPremium(_:)`.
@MainActor
final class FakeSubscriptionService: SubscriptionService {
    private let premium: Broadcast<Bool>
    let userID: String

    init(isPremium: Bool = false, userID: String = "fake-user") {
        premium = Broadcast(isPremium)
        self.userID = userID
    }

    var isPremium: Bool { premium.value }

    func premiumUpdates() -> AsyncStream<Bool> { premium.updates() }

    func setPremium(_ value: Bool) {
        premium.set(value)
    }
}
#endif
