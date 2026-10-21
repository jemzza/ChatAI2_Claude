import StoreKit
import SwiftUI
import UIKit

/// Настройки (макет «Settings»): группы строк, версия приложения внизу.
struct SettingsView: View {
    @StateObject private var model: SettingsViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    init(dependencies: AppDependencies) {
        _model = StateObject(wrappedValue: SettingsViewModel(
            settings: dependencies.settings, scheduler: dependencies.notifications,
            cache: dependencies.cache, subscription: dependencies.subscription
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationHeader("Settings") { router.pop() }
            ScrollView {
                VStack(spacing: AppMetrics.sectionSpacing) {
                    group("Support us") {
                        SettingsRow(systemImage: "star", title: "Rate app") { requestReview() }
                        ShareLink(item: Self.shareMessage) {
                            SettingsRowLabel(systemImage: "square.and.arrow.up", title: "Share with friends")
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                    group("Purchases & Actions") {
                        SettingsRow(systemImage: "sparkles", title: "Upgrade plan") {
                            router.showPaywall(from: .settings)
                        }
                        SettingsRow(systemImage: "bell", title: "Notifications",
                                    accessory: .toggle(Binding(
                                        get: { model.notificationsEnabled },
                                        set: { isOn in Task { await model.toggleNotifications(isOn) } }
                                    )))
                        SettingsRow(systemImage: "trash", title: "Clear cache",
                                    accessory: .chevron(detail: model.cacheSize.map(Self.formatSize))) {
                            Task { await model.clearCache() }
                        }
                        SettingsRow(systemImage: "arrow.clockwise.icloud", title: "Restore purchases",
                                    accessory: .chevron(detail: nil)) {
                            Task { await model.restore() }
                        }
                        .overlay(alignment: .trailing) {
                            if model.isRestoring {
                                ProgressView().tint(.appAccent).padding(.trailing, 40)
                            }
                        }
                    }
                    group("Info & legal") {
                        SettingsRow(systemImage: "text.bubble", title: "Contact us") { open(AppLinks.contact) }
                        SettingsRow(systemImage: "folder.badge.person.crop", title: "Privacy Policy") {
                            open(AppLinks.privacyPolicy)
                        }
                        SettingsRow(systemImage: "doc.text", title: "Usage Policy") { open(AppLinks.usagePolicy) }
                    }
                    Text("App Version: \(SettingsViewModel.appVersion)")
                        .font(.footnote)
                        .foregroundStyle(Color.appLabelTertiary)
                        .padding(16)
                }
                .padding(.vertical, 16)
            }
            .scrollBounceBehaviorIfAvailable()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task { await model.load() }
        .alert(item: $model.alert) { alert in
            switch alert {
            case .notificationsDenied:
                Alert(title: Text("Notifications are turned off"),
                      message: Text("Allow notifications for this app in Settings."),
                      primaryButton: .default(Text("Open Settings")) { openAppSettings() },
                      secondaryButton: .cancel())
            case .restored:
                Alert(title: Text("Purchases restored"), dismissButton: .default(Text("OK")))
            case .nothingToRestore:
                Alert(title: Text("Nothing to restore"),
                      message: Text("No active subscriptions were found for this Apple ID."),
                      dismissButton: .default(Text("OK")))
            case .restoreFailed:
                Alert(title: Text("Restore failed"),
                      message: Text("Couldn't restore purchases. Check your connection and try again."),
                      dismissButton: .default(Text("OK")))
            }
        }
    }

    private func group(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
        VStack(spacing: AppMetrics.cellSpacing) {
            SectionTitle(title: title)
            rows()
                .padding(.horizontal, AppMetrics.sideInset)
        }
    }

    private func open(_ url: URL?) {
        if let url { openURL(url) }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private static var shareMessage: String {
        let text = String(localized: "Try this app: AI chat and photo-to-video templates.")
        return AppLinks.appStore.map { "\(text) \($0.absoluteString)" } ?? text
    }

    /// «5 MB» — системное форматирование размера по локали.
    private static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // «0 KB», а не «Zero KB».
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
