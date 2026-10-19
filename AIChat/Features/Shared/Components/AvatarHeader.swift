import SwiftUI

/// Шапка экранов модулей («AI Chat», «AI Video»): назад, градиентный аватар с иконкой,
/// заголовок и (необязательно) подпись, значок закрепления; справа — действия.
struct AvatarHeader<Trailing: View>: View {
    let icon: String
    let title: LocalizedStringKey
    /// Данные (дата чата) — уже отформатированы.
    var subtitle: String?
    var isPinned = false
    let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            BackButton(action: onBack)
                .frame(width: 24)
                .padding(.trailing, 24)
            HStack(spacing: 12) {
                Image(icon)
                    .frame(width: 24, height: 24)
                    .frame(width: 32, height: 32)
                    .background(AppGradient.primary, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(AppFont.navigationTitle)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(45))
                                .opacity(0.3)
                                .accessibilityLabel(Text("Pinned"))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.subheadline)
                            .opacity(0.3)
                    }
                }
                .foregroundStyle(Color.appAccent)
            }
            Spacer()
            trailing()
                .frame(minWidth: 40, minHeight: 40)
        }
        .padding(16)
        .background(Color.appSurface.opacity(0.4).ignoresSafeArea(edges: .top))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPinned)
    }
}

extension AvatarHeader where Trailing == EmptyView {
    init(icon: String, title: LocalizedStringKey, subtitle: String? = nil, isPinned: Bool = false,
         onBack: @escaping () -> Void) {
        self.init(icon: icon, title: title, subtitle: subtitle, isPinned: isPinned, onBack: onBack) { EmptyView() }
    }
}
