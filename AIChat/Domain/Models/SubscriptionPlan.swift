import Foundation

/// Тариф на пейволе. Цены уже отформатированы магазином (валюта и локаль пользователя).
struct SubscriptionPlan: Identifiable, Hashable, Sendable {
    enum Period: Hashable, Sendable {
        case week
        case month
        case year
        /// Покупка навсегда / неизвестный период.
        case other
    }

    /// Product ID в App Store.
    let id: String
    let period: Period
    /// Цена за весь период — для расчёта выгоды.
    let price: Decimal
    /// Цена за весь период: «$69.99».
    let displayPrice: String
    /// Цена в пересчёте на неделю — для расчёта выгоды.
    let weeklyPrice: Decimal?
    /// Цена в пересчёте на неделю: «$1.27».
    let weeklyDisplayPrice: String?
}

/// Чем закончилась покупка.
enum PurchaseOutcome: Hashable, Sendable {
    case purchased
    /// Пользователь закрыл окно оплаты — не ошибка.
    case cancelled
    /// Ждёт подтверждения (Ask to Buy, SCA): доступ откроется, когда придёт транзакция.
    case pending
}

enum SubscriptionError: Error, Hashable, Sendable {
    /// Пейвол или продукты не загрузились (нет сети, нет продуктов в магазине).
    case productsUnavailable
    case purchaseFailed
    case restoreFailed
}
