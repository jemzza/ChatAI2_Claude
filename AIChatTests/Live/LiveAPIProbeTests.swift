import Foundation
import Testing
@testable import AIChat

/// Ручная проверка настоящего API (шаг 1.3 плана). По умолчанию выключена:
/// `TEST_RUNNER_LIVE_API=1 xcodebuild … test -only-testing:AIChatTests/LiveAPIProbeTests`.
/// Печатает только код ответа и структуру JSON (ключи и типы) — токены не печатаются.
/// Если симулятор не резолвит DNS (`-1003`), тот же код можно собрать для Mac:
/// `swiftc` с этим файлом (без `Testing`) и `Secrets.generated.swift`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_API"] == "1"), .serialized)
struct LiveAPIProbeTests {
    private static let userId = "aichat-probe-user"
    private static let appId = "com.test.test"
    private static let dola = "https://nebulaapps.site/dola"
    private static let pixverse = "https://nebulaapps.site/pixverse"

    private func probe(_ label: String, _ method: String, _ url: String, owner: Bool = true,
                       json: [String: Any]? = nil, showValues: Bool = false) async throws -> Any? {
        var request = URLRequest(url: try #require(URL(string: url)), timeoutInterval: 90)
        request.httpMethod = method
        if owner { request.setValue("Bearer \(Secrets.nebulaAPIToken)", forHTTPHeaderField: "Authorization") }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let object = try? JSONSerialization.jsonObject(with: data)
        let shape = object.map { Self.shape($0, showValues: showValues, depth: 0) } ?? "<\(data.count) bytes, not JSON>"
        print("PROBE \(label): \(status)\n\(shape)\n")
        return object
    }

    /// Структура JSON; значения — только если `showValues` и это не похоже на токен.
    private static func shape(_ value: Any, showValues: Bool, depth: Int) -> String {
        let pad = String(repeating: "  ", count: depth)
        switch value {
        case let dict as [String: Any]:
            return dict.keys.sorted().map { key in
                let child = dict[key] ?? NSNull()
                let isSecret = key.lowercased().contains("token")
                let rendered = isSecret ? "<hidden>" : shape(child, showValues: showValues, depth: depth + 1)
                return "\(pad)\(key): " + (rendered.contains("\n") ? "\n" + rendered : rendered)
            }.joined(separator: "\n")
        case let array as [Any]:
            guard let first = array.first else { return "[]" }
            return "[\(array.count) items] first:\n" + shape(first, showValues: showValues, depth: depth + 1)
        case let string as String:
            return showValues ? "\"\(string.prefix(120))\"" : "String"
        case let number as NSNumber:
            return showValues ? "\(number)" : "Number"
        default:
            return "null"
        }
    }

    private var query: String { "user_id=\(Self.userId)&app_id=\(Self.appId)" }

    @Test func dola() async throws {
        _ = try await probe("dola v1 chats", "GET", "\(Self.dola)/dola/chats?\(query)", showValues: true)
        let chatId = UUID().uuidString.lowercased()
        _ = try await probe("dola v1 send", "POST", "\(Self.dola)/dola/chats/\(chatId)/messages?\(query)",
                            json: ["message": "Hi! Reply with one short sentence."], showValues: true)
        _ = try await probe("dola v1 history", "GET", "\(Self.dola)/dola/chats/\(chatId)/messages?\(query)",
                            showValues: true)
        _ = try await probe("dola v1 no auth", "GET", "\(Self.dola)/dola/chats?\(query)", owner: false, showValues: true)
    }

    @Test func pixverse() async throws {
        _ = try await probe("pixverse v1 templates", "GET", "\(Self.pixverse)/api/v1/get_templates/\(Self.appId)",
                            showValues: true)
        _ = try await probe("pixverse v1 balance", "GET", "\(Self.pixverse)/api/v1/balance?\(query)", showValues: true)
        _ = try await probe("pixverse v1 status unknown", "GET", "\(Self.pixverse)/api/v1/status?id=1&\(query)",
                            showValues: true)
    }
}
