#if DEBUG
import Foundation

/// Подписка, которой управляют вручную: `setPremium(_:)` и сценарии пейвола.
@MainActor
final class FakeSubscriptionService: SubscriptionService {
    private let premium: Broadcast<Bool>
    let userID: String

    /// Что вернёт `paywallPlans()`.
    var plansResult: Result<[SubscriptionPlan], SubscriptionError> = .success(FakeSubscriptionService.samplePlans)
    /// Что вернёт `purchase`; `.purchased` и `.success(true)` у restore делают пользователя premium.
    var purchaseResult: Result<PurchaseOutcome, SubscriptionError> = .success(.purchased)
    var restoreResult: Result<Bool, SubscriptionError> = .success(true)
    /// Задержка ответа — чтобы проверить состояния загрузки.
    var delay: Duration = .zero
    private(set) var purchasedPlanIDs: [SubscriptionPlan.ID] = []
    private(set) var shownCount = 0

    init(isPremium: Bool = false, userID: String = "fake-user") {
        premium = Broadcast(isPremium)
        self.userID = userID
    }

    var isPremium: Bool { premium.value }

    func premiumUpdates() -> AsyncStream<Bool> { premium.updates() }

    func setPremium(_ value: Bool) {
        premium.set(value)
    }

    func paywallPlans() async throws(SubscriptionError) -> [SubscriptionPlan] {
        await wait()
        return try plansResult.get()
    }

    func paywallShown() {
        shownCount += 1
    }

    func purchase(planID: SubscriptionPlan.ID) async throws(SubscriptionError) -> PurchaseOutcome {
        await wait()
        purchasedPlanIDs.append(planID)
        let outcome = try purchaseResult.get()
        if outcome == .purchased { premium.set(true) }
        return outcome
    }

    func restore() async throws(SubscriptionError) -> Bool {
        await wait()
        let restored = try restoreResult.get()
        if restored { premium.set(true) }
        return restored
    }

    private func wait() async {
        if delay > .zero { try? await Task.sleep(for: delay) }
    }

    /// Тарифы как в макете: год и месяц.
    static let samplePlans = [
        SubscriptionPlan(id: "com.labs.fviu.year", period: .year, price: 69.99, displayPrice: "$69.99",
                         weeklyPrice: 69.99 / 52, weeklyDisplayPrice: "$1.35"),
        SubscriptionPlan(id: "com.labs.fviu.month", period: .month, price: 7.99, displayPrice: "$7.99",
                         weeklyPrice: 7.99 * 12 / 52, weeklyDisplayPrice: "$1.84"),
    ]
}
#endif
