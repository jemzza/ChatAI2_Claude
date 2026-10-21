#if DEBUG
import Foundation

/// Кэш в памяти — для тестов и превью.
final class FakeCacheManager: CacheManaging {
    private let bytes: Locked<Int64>

    init(size: Int64 = 5_000_000) {
        bytes = Locked(size)
    }

    func size() async -> Int64 { bytes.withLock { $0 } }
    func clear() async { bytes.withLock { $0 = 0 } }
}
#endif
