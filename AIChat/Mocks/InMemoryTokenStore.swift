#if DEBUG
import Foundation

/// Токены в памяти — для тестов.
final class InMemoryTokenStore: TokenStoring {
    private let storage = Locked<[String: SessionTokens]>([:])

    init(_ initial: [String: SessionTokens] = [:]) {
        storage.withLock { $0 = initial }
    }

    func load(key: String) -> SessionTokens? { storage.withLock { $0[key] } }
    func save(_ tokens: SessionTokens, key: String) { storage.withLock { $0[key] = tokens } }
    func remove(key: String) { storage.withLock { _ = $0.removeValue(forKey: key) } }
}
#endif
