#if DEBUG
import SwiftUI

/// Все общие компоненты на одном экране — для сверки с Figma (`-componentGallery`).
/// Тексты — из макета.
struct ComponentGallery: View {
    @State private var text = ""
    @State private var toast: ToastMessage?
    @State private var notifications = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NavigationHeader("Settings", onBack: {}) { Image("ButtonMore") }
            ScrollView {
                VStack(spacing: 20) {
                    GradientButton(title: "Unlock now") { toast = ToastMessage(kind: .success, text: "Copied") }
                    GradientButton(title: "Create", isEnabled: false) {}
                    HStack {
                        ChipButton(title: "Explain simply") { toast = ToastMessage(kind: .failure, text: "Copy failed") }
                        ChipButton(title: "Cartoon", isSelected: true) {}
                        ChipButton(title: "Popular", isSelected: true, style: .filled) {}
                    }
                    VStack(spacing: AppMetrics.cellSpacing) {
                        SectionTitle(title: "Purchases & Actions")
                        SettingsRow(systemImage: "sparkles", title: "Upgrade plan")
                        SettingsRow(systemImage: "bell", title: "Notifications", accessory: .toggle($notifications))
                        SettingsRow(systemImage: "trash", title: "Clear cache", accessory: .chevron(detail: "5 MB"))
                    }
                    ToastView(message: ToastMessage(kind: .success, text: "Copied"))
                    ToastView(message: ToastMessage(kind: .failure, text: "Upload failed"))
                }
                .padding(.horizontal, AppMetrics.sideInset)
            }
            MessageInputBar(text: $text, placeholder: "How can I help you?", isSendEnabled: !text.isEmpty,
                            focus: $focused) {}
        }
        .background(Color.appBackground.ignoresSafeArea())
        .toast($toast)
    }
}
#endif
