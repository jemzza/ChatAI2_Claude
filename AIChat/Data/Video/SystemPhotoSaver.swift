import Photos

/// `PhotoSaving` на `PHPhotoLibrary`: запрашивает только добавление (без чтения галереи).
@MainActor
final class SystemPhotoSaver: PhotoSaving {
    struct AccessDenied: Error {}

    func saveVideo(at fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AccessDenied() }
        try await PHPhotoLibrary.shared().performChanges(Self.creationRequest(for: fileURL))
    }

    /// Блок изменений Photos выполняет на своей очереди. Замыкание, написанное внутри
    /// `@MainActor`-класса, унаследовало бы изоляцию, и Swift 6 упал бы на проверке
    /// (SIGTRAP при «Download»). Поэтому блок собирается вне актора.
    private nonisolated static func creationRequest(for fileURL: URL) -> @Sendable () -> Void {
        { _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL) }
    }
}
