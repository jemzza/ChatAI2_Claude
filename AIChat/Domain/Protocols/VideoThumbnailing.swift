import Foundation

/// Кадр-превью из видео по ссылке (шаблоны PixVerse приходят как mp4).
protocol VideoThumbnailing: Sendable {
    /// JPEG первого кадра, длинная сторона не больше `maxPixelSize`; `nil` — не получилось.
    func thumbnail(for url: URL, maxPixelSize: Int) async -> Data?
}
