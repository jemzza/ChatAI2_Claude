import Foundation

/// Сохранение видео в «Фото». Реализация — `PHPhotoLibrary` (add-only доступ).
@MainActor
protocol PhotoSaving: AnyObject {
    /// - Throws: нет доступа или не удалось сохранить.
    func saveVideo(at fileURL: URL) async throws
}
