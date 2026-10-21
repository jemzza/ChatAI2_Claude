import Foundation

/// Кэш, который можно пересоздать: скачанные видео и кадры превью («Clear cache»).
/// История и исходные фото генераций не трогаются.
protocol CacheManaging: Sendable {
    /// Размер в байтах.
    func size() async -> Int64
    func clear() async
}
