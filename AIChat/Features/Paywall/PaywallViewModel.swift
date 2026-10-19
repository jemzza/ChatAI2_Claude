import Foundation

/// Пейвол: тарифы из Apphud, выбор, покупка, restore, крестик с задержкой.
/// Экран закрывается сам, как только подписка стала активной (`isFinished`) —
/// неважно, откуда пришла покупка.
@MainActor
final class PaywallViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    struct PlanOption: Identifiable, Equatable {
        let id: SubscriptionPlan.ID
        let period: SubscriptionPlan.Period
        /// «$1.27» — цена за неделю; `nil` — период неизвестен.
        let weeklyPrice: String?
        /// «$69.99» — цена за весь период.
        let totalPrice: String
        /// Выгода относительно самого дорогого в неделю тарифа, «80» → «SAVE 80%».
        let savingsPercent: Int?
    }

    enum Alert: Identifiable, Equatable {
        case purchaseFailed
        case purchasePending
        case restoreFailed
        case nothingToRestore

        var id: Self { self }
    }

    @Published private(set) var state = State.loading
    @Published private(set) var options: [PlanOption] = []
    @Published var selectedPlanID: SubscriptionPlan.ID?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    /// Крестик появляется не сразу (заметка к макету пейвола).
    @Published private(set) var isCloseButtonVisible = false
    @Published var alert: Alert?
    /// Пейвол пора закрыть: подписка активна или пользователь нажал крестик.
    @Published private(set) var isFinished = false

    private let subscription: any SubscriptionService
    private let closeButtonDelay: Duration

    init(subscription: any SubscriptionService, closeButtonDelay: Duration = .seconds(2)) {
        self.subscription = subscription
        self.closeButtonDelay = closeButtonDelay
    }

    var isBusy: Bool { isPurchasing || isRestoring }

    /// Живёт, пока экран на экране (`.task`): загрузка, таймер крестика, слежение за подпиской.
    func start() async {
        async let loading: Void = load()
        async let closeButton: Void = revealCloseButton()
        async let premium: Void = finishWhenPremium()
        _ = await (loading, closeButton, premium)
    }

    func load() async {
        state = .loading
        do {
            let plans = try await subscription.paywallPlans()
            options = Self.options(from: plans)
            if selectedPlanID == nil || !options.contains(where: { $0.id == selectedPlanID }) {
                selectedPlanID = (options.first { $0.savingsPercent != nil } ?? options.first)?.id
            }
            state = .loaded
            subscription.paywallShown()
        } catch {
            state = .failed
        }
    }

    func purchase() async {
        guard let selectedPlanID, !isBusy else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await subscription.purchase(planID: selectedPlanID) {
            case .purchased: isFinished = true
            case .cancelled: break
            case .pending: alert = .purchasePending
            }
        } catch {
            alert = .purchaseFailed
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            if try await subscription.restore() {
                isFinished = true
            } else {
                alert = .nothingToRestore
            }
        } catch {
            alert = .restoreFailed
        }
    }

    func close() {
        isFinished = true
    }

    private func revealCloseButton() async {
        try? await Task.sleep(for: closeButtonDelay)
        guard !Task.isCancelled else { return }
        isCloseButtonVisible = true
    }

    private func finishWhenPremium() async {
        for await isPremium in subscription.premiumUpdates() where isPremium {
            isFinished = true
            return
        }
    }

    static func options(from plans: [SubscriptionPlan]) -> [PlanOption] {
        let maxWeekly = plans.compactMap(\.weeklyPrice).max()
        return plans.map { plan in
            var savings: Int?
            if let maxWeekly, maxWeekly > 0, let weekly = plan.weeklyPrice, weekly < maxWeekly {
                // `NSDecimalNumber.intValue` ошибается на длинных дробях — сначала округляем.
                var exact = (maxWeekly - weekly) / maxWeekly * 100
                var rounded = Decimal()
                NSDecimalRound(&rounded, &exact, 0, .plain)
                let percent = NSDecimalNumber(decimal: rounded).intValue
                savings = percent > 0 ? percent : nil
            }
            return PlanOption(id: plan.id, period: plan.period, weeklyPrice: plan.weeklyDisplayPrice,
                              totalPrice: plan.displayPrice, savingsPercent: savings)
        }
    }
}
