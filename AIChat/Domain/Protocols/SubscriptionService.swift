import Foundation

/// Подписка пользователя. Реализация — Apphud (`Data/Subscription`), фейк — `Mocks/`.
/// ViewModel работают только с этим протоколом и не знают про ApphudSDK.
@MainActor
protocol SubscriptionService: AnyObject, Sendable {
    /// Есть ли сейчас полный доступ (активная подписка или покупка).
    var isPremium: Bool { get }

    /// `isPremium`: текущее значение сразу, дальше — каждое изменение
    /// (покупка, restore, истечение). Доступ открывается без перезапуска.
    func premiumUpdates() -> AsyncStream<Bool>

    /// ID пользователя для API (`user_id`) — Apphud User ID.
    var userID: String { get }

    /// Тарифы пейвола `main` в порядке из Apphud.
    func paywallPlans() async throws(SubscriptionError) -> [SubscriptionPlan]

    /// Отметка «пейвол показан» — для аналитики Apphud.
    func paywallShown()

    /// Покупка тарифа. Ошибка — `SubscriptionError.purchaseFailed`; отмена — `.cancelled`.
    func purchase(planID: SubscriptionPlan.ID) async throws(SubscriptionError) -> PurchaseOutcome

    /// Restore Purchases. Возвращает `isPremium` после восстановления.
    func restore() async throws(SubscriptionError) -> Bool
}
