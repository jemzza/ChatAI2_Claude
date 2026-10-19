import Foundation

/// События `VideoGenerationService` для уведомлений. `async` — сервис ждёт обработку,
/// пока у него есть фоновое время.
@MainActor
protocol VideoEventHandling: AnyObject {
    /// Видео готово (`succeeded`).
    func videoDidFinish(generationId: UUID, templateName: String) async
}
