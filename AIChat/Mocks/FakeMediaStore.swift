#if DEBUG
import Foundation

/// Файлы генераций в памяти — для тестов и превью.
final class FakeMediaStore: MediaStoring {
    private struct State {
        var images: [String: Data] = [:]
        var videos: Set<String> = []
        var downloadResult: Result<Void, APIError> = .success(())
        var downloads: [URL] = []
    }

    private let state = Locked(State())

    var savedImages: [String: Data] { state.withLock(\.images) }
    var videos: Set<String> { state.withLock(\.videos) }
    var downloads: [URL] { state.withLock(\.downloads) }

    func setDownloadResult(_ result: Result<Void, APIError>) {
        state.withLock { $0.downloadResult = result }
    }

    /// «Не картинка» — пустые данные.
    func saveSourceImage(_ data: Data, aspect: VideoAspect) async -> String? {
        guard !data.isEmpty else { return nil }
        let name = "\(UUID().uuidString).jpg"
        state.withLock { $0.images[name] = data }
        return name
    }

    func sourceImage(named name: String) -> Data? { state.withLock { $0.images[name] } }

    func sourceImageURL(named name: String) -> URL { URL(fileURLWithPath: "/fake/sources/\(name)") }

    func downloadVideo(from url: URL) async throws -> String {
        try state.withLock { state in
            state.downloads.append(url)
            try state.downloadResult.get()
            let name = "\(UUID().uuidString).mp4"
            state.videos.insert(name)
            return name
        }
    }

    func videoURL(named name: String) -> URL { URL(fileURLWithPath: "/fake/videos/\(name)") }

    func deleteFiles(sourceImageName: String?, videoName: String?) {
        state.withLock { state in
            if let sourceImageName { state.images[sourceImageName] = nil }
            if let videoName { state.videos.remove(videoName) }
        }
    }
}
#endif
