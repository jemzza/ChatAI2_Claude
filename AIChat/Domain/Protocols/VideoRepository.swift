import Foundation

/// Единственный источник правды о генерациях видео.
protocol VideoRepository: Sendable {
    /// Все генерации, новые сверху. Первое значение — сразу, дальше — при каждом изменении.
    func observeGenerations() -> AsyncStream<[VideoGeneration]>
    /// Одна генерация; `nil` — её нет (удалена).
    func observeGeneration(id: UUID) -> AsyncStream<VideoGeneration?>

    func insert(_ generation: VideoGeneration) async throws
    /// Записывает генерацию целиком.
    /// - Throws: `VideoGenerationNotFound`.
    func update(_ generation: VideoGeneration) async throws
    /// - Throws: `VideoGenerationNotFound`.
    func generation(id: UUID) async throws -> VideoGeneration
    /// Отсутствующая генерация — не ошибка.
    func delete(id: UUID) async throws
    /// Генерации `creating`/`generating`, старые первыми — их продолжаем после запуска.
    func activeGenerations() async throws -> [VideoGeneration]
}
