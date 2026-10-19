import Foundation

/// Внешние ссылки приложения. Privacy Policy и Usage Policy заказчик ещё не дал
/// (открытый вопрос в docs/task.md) — пока `nil`, кнопки ничего не открывают.
enum AppLinks {
    /// Стандартное лицензионное соглашение Apple (EULA) — «Terms of Use» на пейволе.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    static let privacyPolicy: URL? = nil
    static let usagePolicy: URL? = nil
}
