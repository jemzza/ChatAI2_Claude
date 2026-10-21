import SwiftUI

/// Строка настроек: градиентная иконка SF Symbols, название, справа — значение и шеврон
/// или переключатель. Капсула 44pt на полупрозрачной подложке.
struct SettingsRow: View {
    enum Accessory {
        case chevron(detail: String? = nil)
        case toggle(Binding<Bool>)
    }

    let systemImage: String
    let title: LocalizedStringKey
    var accessory = Accessory.chevron()
    var action: () -> Void = {}

    var body: some View {
        switch accessory {
        case .chevron:
            Button(action: action) { content }
                .buttonStyle(PressableButtonStyle())
        case .toggle:
            content
        }
    }

    /// Только внешний вид (без кнопки) — внутрь чужих контролов.
    var labelOnly: some View { content }

    private var content: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(AppGradient.primary)
                .frame(width: 28)
                .padding(.trailing, 8)
            Text(title)
                .font(AppFont.body)
                .foregroundStyle(Color.appAccent)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: AppMetrics.rowHeight)
        .background(Color.appSurface.opacity(0.4), in: Capsule())
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var trailing: some View {
        switch accessory {
        case let .chevron(detail):
            HStack(spacing: 16) {
                if let detail {
                    // Значение — данные (размер кэша), уже отформатированные.
                    Text(detail)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppGradient.primary)
            }
        case let .toggle(isOn):
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .tint(.appGradientEnd)
        }
    }
}

/// Вид строки с шевроном без действия — для `ShareLink` и других обёрток.
struct SettingsRowLabel: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        SettingsRow(systemImage: systemImage, title: title).labelOnly
    }
}

/// Заголовок группы строк: Inter SemiBold 16, 30% белого.
struct SectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(AppFont.headline)
            .foregroundStyle(Color.appAccent.opacity(0.3))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppMetrics.sideInset)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: AppMetrics.cellSpacing) {
        SectionTitle(title: "Support us")
        SettingsRow(systemImage: "star", title: "Rate app")
        SettingsRow(systemImage: "bell", title: "Notifications", accessory: .toggle(.constant(false)))
        SettingsRow(systemImage: "trash", title: "Clear cache", accessory: .chevron(detail: "5 MB"))
    }
    .padding(.horizontal, AppMetrics.sideInset)
    .frame(maxHeight: .infinity)
    .background(Color.appBackground)
}
#endif
