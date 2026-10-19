import SwiftUI

/// Пейвол (макет «paywall»): преимущества, тарифы из Apphud, «Unlock now», Restore и ссылки.
/// Крестик появляется через 2 с; после покупки экран закрывается сам.
struct PaywallView: View {
    @StateObject private var model: PaywallViewModel
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL

    init(subscription: any SubscriptionService, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: PaywallViewModel(subscription: subscription))
        self.onClose = onClose
    }

    private struct Benefit: Identifiable {
        let icon: String
        let title: LocalizedStringKey
        var id: String { icon }
    }

    private static let benefits = [
        Benefit(icon: "IconGenerate", title: "Get results in seconds"),
        Benefit(icon: "IconMagicPencil", title: "Turn any text into better writing"),
        Benefit(icon: "IconPrompt", title: "Simplify complex information"),
        Benefit(icon: "IconImageToImage", title: "Create content with AI templates"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppMetrics.sideInset)
                    .padding(.vertical, 16)
            }
            .scrollBounceBehaviorIfAvailable()
            bottomBar
        }
        .background(GlowBackground())
        .overlay(alignment: .topLeading) { closeButton }
        .task { await model.start() }
        .onChange(of: model.isFinished) { finished in
            if finished { onClose() }
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alertTitle(alert)), message: Text(alertMessage(alert)),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: Контент

    private var content: some View {
        VStack(spacing: 24) {
            Image("Mascot")
                .resizable()
                .scaledToFill()
                .frame(width: 135, height: 92)
                .accessibilityHidden(true)
            VStack(spacing: 32) {
                Text("Create anything\nyou want")
                    .font(AppFont.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.appAccent)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.benefits) { benefit in
                        HStack(spacing: 8) {
                            Image(benefit.icon)
                                .frame(width: 24, height: 24)
                            Text(benefit.title)
                                .font(AppFont.bodyMedium)
                                .foregroundStyle(Color.appAccent)
                        }
                        .frame(height: 32)
                    }
                }
                plans
            }
        }
    }

    @ViewBuilder
    private var plans: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AppMetrics.cardRadius)
                        .strokeBorder(Color.appStroke)
                        .frame(height: 74)
                        .overlay(ProgressView().tint(.appAccent))
                }
            }
        case .failed:
            VStack(spacing: 12) {
                Text("Couldn't load plans")
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.appAccent)
                Text("Check your connection and try again.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                Button {
                    Task { await model.load() }
                } label: {
                    Text("Try again")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(Color.appStroke))
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        case .loaded:
            VStack(spacing: 12) {
                ForEach(model.options) { option in
                    PlanCard(option: option, isSelected: option.id == model.selectedPlanID) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.selectedPlanID = option.id }
                    }
                }
            }
        }
    }

    // MARK: Низ экрана

    private var bottomBar: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Cancel Anytime")
            }
            .font(AppFont.systemCaption)
            .foregroundStyle(Color.appTextSecondary)
            .padding(.vertical, 8)
            // Не нажимается (заметка к макету).
            .accessibilityElement(children: .combine)

            GradientButton(title: "Unlock now", isEnabled: model.state == .loaded && model.selectedPlanID != nil,
                           isLoading: model.isPurchasing) {
                Task { await model.purchase() }
            }
            .padding(.horizontal, AppMetrics.sideInset)

            HStack(spacing: 12) {
                linkButton("Privacy Policy", url: AppLinks.privacyPolicy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await model.restore() }
                } label: {
                    if model.isRestoring {
                        ProgressView().controlSize(.mini).tint(.appTextSecondary)
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .disabled(model.isBusy)
                linkButton("Terms of Use", url: AppLinks.termsOfUse)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(AppFont.systemCaption2)
            .foregroundStyle(Color.appTextSecondary)
            .lineLimit(1)
            .padding(.horizontal, AppMetrics.sideInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private func linkButton(_ title: LocalizedStringKey, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Text(title)
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if model.isCloseButtonVisible {
            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .opacity(0.7)
            .padding(.leading, 6)
            .padding(.top, 6)
            .transition(.opacity)
            .accessibilityLabel(Text("Close"))
        }
    }

    // MARK: Алерты

    private func alertTitle(_ alert: PaywallViewModel.Alert) -> LocalizedStringKey {
        switch alert {
        case .purchaseFailed: "Purchase failed"
        case .purchasePending: "Purchase pending"
        case .restoreFailed: "Restore failed"
        case .nothingToRestore: "Nothing to restore"
        }
    }

    private func alertMessage(_ alert: PaywallViewModel.Alert) -> LocalizedStringKey {
        switch alert {
        case .purchaseFailed: "Something went wrong. Please try again."
        case .purchasePending: "Your purchase is waiting for approval. Access will open as soon as it's confirmed."
        case .restoreFailed: "Couldn't restore purchases. Check your connection and try again."
        case .nothingToRestore: "No active subscriptions were found for this Apple ID."
        }
    }
}

/// Карточка тарифа: «Year $1.27 / week», под ней полная цена; у выбранной — градиентная
/// обводка и бейдж выгоды.
struct PlanCard: View {
    let option: PaywallViewModel.PlanOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        title.font(AppFont.bodyMedium)
                        if option.weeklyPrice != nil {
                            Text("/ week").font(AppFont.body)
                        }
                    }
                    .foregroundStyle(Color.appAccent)
                    // Цена — из магазина, уже в валюте пользователя.
                    Text(option.totalPrice)
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                if isSelected, let savings = option.savingsPercent {
                    Text("SAVE \(savings)%")
                        .font(AppFont.subheadlineMedium)
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(AppGradient.primary, in: Capsule())
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(border)
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: Text {
        let price = option.weeklyPrice ?? option.totalPrice
        switch option.period {
        case .year: return Text("Year \(price)")
        case .month: return Text("Month \(price)")
        case .week: return Text("Week \(price)")
        case .other: return Text("Lifetime \(price)")
        }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: AppMetrics.cardRadius)
        if isSelected {
            shape.strokeBorder(AppGradient.primary, lineWidth: 1)
        } else {
            shape.strokeBorder(Color.appStroke, lineWidth: 1)
        }
    }
}

extension View {
    /// Без «резинки», если контент помещается (iOS 16.4+).
    @ViewBuilder
    func scrollBounceBehaviorIfAvailable() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

#if DEBUG
#Preview("Loaded") {
    PaywallView(subscription: FakeSubscriptionService()) {}
}

#Preview("Failed") {
    let subscription = FakeSubscriptionService()
    subscription.plansResult = .failure(.productsUnavailable)
    return PaywallView(subscription: subscription) {}
}
#endif
