import Photos

/// `PhotoSaving` на `PHPhotoLibrary`: запрашивает только добавление (без чтения галереи).
@MainActor
final class SystemPhotoSaver: PhotoSaving {
    struct AccessDenied: Error {}

    func saveVideo(at fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AccessDenied() }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }
}
