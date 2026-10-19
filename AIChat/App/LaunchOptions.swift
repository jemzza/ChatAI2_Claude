import Foundation

/// DEBUG-хуки из launch-аргументов. Без аргументов (и всегда в Release) — `.none`:
/// `AppContainer` собирает только реальные реализации.
///
/// - `-mockData` — репозиторий в памяти с `PreviewData`;
/// - `-mockOffline` — сеть всегда «нет»;
/// - `-mockError 429|401|402|403|500|offline` — сеть отвечает этой ошибкой;
/// - `-mockSlowReply` — фейковый AI отвечает через несколько секунд;
/// - `-mockPremium` / `-mockFree` — подписка-фейк с активной подпиской / без неё;
/// - `-componentGallery` — вместо приложения экран со всеми общими компонентами.
struct LaunchOptions: Hashable, Sendable {
    var useMockData = false
    var forceOffline = false
    var mockError: ErrorKind?
    var slowReply = false
    /// `nil` — настоящий Apphud.
    var mockPremium: Bool?
    var showComponentGallery = false

    static let none = LaunchOptions()

    var usesMocks: Bool { self != .none }

    init() {}

    init(arguments: [String]) {
        #if DEBUG
        useMockData = arguments.contains("-mockData")
        forceOffline = arguments.contains("-mockOffline")
        slowReply = arguments.contains("-mockSlowReply")
        showComponentGallery = arguments.contains("-componentGallery")
        if arguments.contains("-mockPremium") {
            mockPremium = true
        } else if arguments.contains("-mockFree") {
            mockPremium = false
        }
        if let index = arguments.firstIndex(of: "-mockError") {
            let value = arguments.index(after: index) < arguments.endIndex ? arguments[index + 1] : ""
            mockError = Self.errorKind(for: value)
        }
        #endif
    }

    private static func errorKind(for value: String) -> ErrorKind {
        switch value {
        case "429": .rateLimited
        case "401": .unauthorized
        case "402": .paymentRequired
        case "403": .forbidden
        case "500": .server
        case "offline": .offline
        default: .unknown
        }
    }
}
