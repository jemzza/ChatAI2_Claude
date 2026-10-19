import Foundation

/// Файлы генераций: исходные фото (нужны для «Try again») и скачанные видео (кэш).
/// В базе хранятся только имена файлов — путь к контейнеру между установками меняется.
protocol MediaStoring: Sendable {
    /// Кадрирует фото под формат и сохраняет. `nil` — это не картинка («Upload failed»).
    func saveSourceImage(_ data: Data, aspect: VideoAspect) async -> String?
    func sourceImage(named name: String) -> Data?
    func sourceImageURL(named name: String) -> URL
    /// Скачивает результат в кэш видео. - Returns: имя файла.
    func downloadVideo(from url: URL) async throws -> String
    func videoURL(named name: String) -> URL
    /// Удаляет файлы генерации; отсутствующие — не ошибка.
    func deleteFiles(sourceImageName: String?, videoName: String?)
}
