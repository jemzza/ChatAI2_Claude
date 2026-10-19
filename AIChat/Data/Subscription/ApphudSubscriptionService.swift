import ApphudSDK
import Foundation

/// `SubscriptionService` на Apphud. Создаётся один раз в `AppContainer`;
/// SDK стартует в инициализаторе — до первого запроса к API, которому нужен `userID`.
@MainActor
final class ApphudSubscriptionService: SubscriptionService {
    private let premium: Broadcast<Bool>
    private var updatesTask: Task<Void, Never>?

    init(apiKey: String) {
        Apphud.start(apiKey: apiKey)
        premium = Broadcast(Apphud.hasPremiumAccess())
        // Покупка, restore, продление и возврат в приложение — SDK шлёт это уведомление.
        updatesTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: Apphud.didUpdateNotification()) {
                self?.refresh()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var isPremium: Bool { premium.value }

    func premiumUpdates() -> AsyncStream<Bool> { premium.updates() }

    var userID: String { Apphud.userID() }

    private func refresh() {
        premium.set(Apphud.hasPremiumAccess())
    }
}
