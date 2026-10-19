import Foundation

/// Состояние генерации на сервере.
enum VideoServerStatus: Hashable, Sendable {
    case generating
    case succeeded(URL)
    case failed
}

/// Сервис генерации видео (PixVerse). Ошибки — `APIError`; отмена — `CancellationError`.
protocol VideoAPI: Sendable {
    /// Активные шаблоны в порядке каталога. Без сети — последний сохранённый каталог.
    func templates() async throws -> [VideoTemplate]
    /// Запускает генерацию по шаблону и фото (JPEG). Возвращает `video_id`.
    func createVideo(templateId: Int64, imageJPEG: Data, quality: VideoQuality, duration: Int?) async throws -> Int64
    func status(serverId: Int64) async throws -> VideoServerStatus
}
