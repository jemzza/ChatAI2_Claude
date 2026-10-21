#if DEBUG
import Foundation

/// API видео для `-mockData`: каталог — образцы `FakeVideoAPI`, «генерация» —
/// несколько ответов `generating`, затем локальный mp4 из присланного фото
/// (`FakeVideoRenderer`). Так весь путь Create → генерация → результат →
/// Download/Share проверяется без сети.
final class DemoVideoAPI: VideoAPI {
    private struct State {
        var lastId: Int64 = 900_000
        var polls: [Int64: Int] = [:]
    }

    private let state = Locked(State())
    private let directory: URL
    private let pendingPolls: Int

    init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("DemoVideos", isDirectory: true),
         pendingPolls: Int = 2) {
        self.directory = directory
        self.pendingPolls = pendingPolls
    }

    func templates() async throws -> [VideoTemplate] {
        FakeVideoAPI.sampleTemplates
    }

    func createVideo(templateId: Int64, imageJPEG: Data, quality: VideoQuality, duration: Int?) async throws -> Int64 {
        let id = state.withLock { state in
            state.lastId += 1
            return state.lastId
        }
        let url = videoURL(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await Task.detached(priority: .utility) {
            try FakeVideoRenderer.render(jpeg: imageJPEG, to: url)
        }.value
        return id
    }

    func status(serverId: Int64) async throws -> VideoServerStatus {
        let polls = state.withLock { state in
            let count = state.polls[serverId, default: 0] + 1
            state.polls[serverId] = count
            return count
        }
        let url = videoURL(serverId)
        guard FileManager.default.fileExists(atPath: url.path) else { throw APIError(kind: .notFound) }
        return polls > pendingPolls ? .succeeded(url) : .generating
    }

    private func videoURL(_ id: Int64) -> URL {
        directory.appendingPathComponent("\(id).mp4", isDirectory: false)
    }
}
#endif
