import Foundation

/// Доступ к фото: перед выбором показываем системный запрос (заметка к макету
/// «Photo Permission»). Реализация — `PHPhotoLibrary`, фейк — в тестах.
@MainActor
protocol PhotoLibraryAccess: AnyObject {
    /// Запрашивает доступ, если его ещё не спрашивали. `true` — можно открыть галерею.
    func requestAccess() async -> Bool
}
