import Foundation

/// `MediaStoring` на файлах: фото — в Application Support (не чистится системой),
/// видео — в Caches (можно скачать заново, «Clear cache» в настройках).
struct FileMediaStore: MediaStoring {
    /// Длинная сторона фото для генерации: 1080p хватает любому качеству API.
    static let sourceImageMaxPixelSize = 1920

    private let sourcesDirectory: URL
    private let videosDirectory: URL
    private let session: URLSession

    init(sourcesDirectory: URL, videosDirectory: URL, session: URLSession = .shared) {
        self.sourcesDirectory = sourcesDirectory
        self.videosDirectory = videosDirectory
        self.session = session
    }

    /// Папки приложения по умолчанию.
    static func standard() throws -> FileMediaStore {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
        let caches = try manager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FileMediaStore(sourcesDirectory: support.appendingPathComponent("VideoSources", isDirectory: true),
                              videosDirectory: caches.appendingPathComponent("Videos", isDirectory: true))
    }

    func saveSourceImage(_ data: Data, aspect: VideoAspect) async -> String? {
        // Декодирование и кроп — не на главном потоке.
        let jpeg = await Task.detached(priority: .userInitiated) {
            ImageDownscaler.jpeg(from: data, croppedTo: aspect.ratio, maxPixelSize: Self.sourceImageMaxPixelSize)
        }.value
        guard let jpeg else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
            try jpeg.write(to: sourceImageURL(named: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func sourceImage(named name: String) -> Data? {
        try? Data(contentsOf: sourceImageURL(named: name))
    }

    func sourceImageURL(named name: String) -> URL {
        sourcesDirectory.appendingPathComponent(name, isDirectory: false)
    }

    func downloadVideo(from url: URL) async throws -> String {
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(from: url)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIErrorMapper.error(error)
        }
        if let http = response as? HTTPURLResponse,
           let error = APIErrorMapper.error(statusCode: http.statusCode, headers: http.allHeaderFields) {
            throw error
        }
        let name = "\(UUID().uuidString).mp4"
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporary, to: videoURL(named: name))
        return name
    }

    func videoURL(named name: String) -> URL {
        videosDirectory.appendingPathComponent(name, isDirectory: false)
    }

    func localVideoURL(named name: String) -> URL? {
        let url = videoURL(named: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func deleteFiles(sourceImageName: String?, videoName: String?) {
        if let sourceImageName { try? FileManager.default.removeItem(at: sourceImageURL(named: sourceImageName)) }
        if let videoName { try? FileManager.default.removeItem(at: videoURL(named: videoName)) }
    }
}
