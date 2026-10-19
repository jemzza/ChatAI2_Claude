import Photos

/// `PhotoLibraryAccess` на `PHPhotoLibrary`. Ограниченный доступ — тоже доступ.
@MainActor
final class SystemPhotoLibraryAccess: PhotoLibraryAccess {
    func requestAccess() async -> Bool {
        switch await PHPhotoLibrary.requestAuthorization(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }
}
