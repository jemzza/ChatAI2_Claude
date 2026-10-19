import ApphudSDK
import Foundation
import StoreKit

/// `SubscriptionService` на Apphud. Создаётся один раз в `AppContainer`;
/// SDK стартует в инициализаторе — до первого запроса к API, которому нужен `userID`.
@MainActor
final class ApphudSubscriptionService: SubscriptionService {
    /// Пейвол из ТЗ.
    static let paywallID = "main"

    private let premium: Broadcast<Bool>
    private var updatesTask: Task<Void, Never>?
    private var paywall: ApphudPaywall?

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

    // MARK: Пейвол

    func paywallPlans() async throws(SubscriptionError) -> [SubscriptionPlan] {
        let placements = await Apphud.placements()
        // `main` — id пейвола; на случай, если в дашборде так назван плейсмент, ищем и его.
        let paywall = placements.lazy.compactMap(\.paywall).first { $0.identifier == Self.paywallID }
            ?? placements.first { $0.identifier == Self.paywallID }?.paywall
        guard let paywall else { throw .productsUnavailable }
        self.paywall = paywall

        var plans: [SubscriptionPlan] = []
        for product in paywall.products {
            guard let storeProduct = try? await product.product() else { continue }
            plans.append(Self.plan(from: storeProduct))
        }
        guard !plans.isEmpty else { throw .productsUnavailable }
        return plans
    }

    func paywallShown() {
        if let paywall { Apphud.paywallShown(paywall) }
    }

    func purchase(planID: SubscriptionPlan.ID) async throws(SubscriptionError) -> PurchaseOutcome {
        guard let product = paywall?.products.first(where: { $0.productId == planID }) else {
            throw .purchaseFailed
        }
        let result = await Apphud.purchase(product)
        refresh()
        if result.userCanceled { return .cancelled }
        if result.isPending { return .pending }
        guard result.error == nil, result.success || isPremium else { throw .purchaseFailed }
        return .purchased
    }

    func restore() async throws(SubscriptionError) -> Bool {
        let result = await Apphud.restorePurchases()
        refresh()
        if result?.error != nil, !isPremium { throw .restoreFailed }
        return isPremium
    }

    private func refresh() {
        premium.set(Apphud.hasPremiumAccess())
    }

    // MARK: Цены

    /// Недель в периоде подписки.
    private static func weeks(in period: Product.SubscriptionPeriod) -> Decimal? {
        let value = Decimal(period.value)
        switch period.unit {
        case .day: return value / 7
        case .week: return value
        case .month: return value * 52 / 12
        case .year: return value * 52
        @unknown default: return nil
        }
    }

    private static func plan(from product: Product) -> SubscriptionPlan {
        let period = product.subscription?.subscriptionPeriod
        let weekly = period.flatMap(weeks(in:)).map { product.price / $0 }
        return SubscriptionPlan(
            id: product.id,
            period: period.map(Self.period(from:)) ?? .other,
            price: product.price,
            displayPrice: product.displayPrice,
            weeklyPrice: weekly,
            weeklyDisplayPrice: weekly.map { product.priceFormatStyle.format($0) }
        )
    }

    private static func period(from period: Product.SubscriptionPeriod) -> SubscriptionPlan.Period {
        switch (period.unit, period.value) {
        case (.week, 1), (.day, 7): .week
        case (.month, 1): .month
        case (.year, 1): .year
        default: .other
        }
    }
}
