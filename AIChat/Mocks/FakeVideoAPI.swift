#if DEBUG
import Foundation

/// Генерация видео по сценарию — для тестов, превью и DEBUG launch-аргументов.
final class FakeVideoAPI: VideoAPI {
    struct Create: Hashable, Sendable {
        let templateId: Int64
        let imageJPEG: Data
        let quality: VideoQuality
    }

    private struct State {
        var templates: Result<[VideoTemplate], APIError>
        var createResult: Result<Int64, APIError> = .success(900_001)
        /// Ответы `status` по очереди; последний повторяется.
        var statuses: [Result<VideoServerStatus, APIError>]
        var creates: [Create] = []
        var statusRequests = 0
    }

    private let state: Locked<State>

    init(
        templates: Result<[VideoTemplate], APIError> = .success(FakeVideoAPI.sampleTemplates),
        statuses: [Result<VideoServerStatus, APIError>] = [.success(.succeeded(FakeVideoAPI.sampleVideoURL))]
    ) {
        state = Locked(State(templates: templates, statuses: statuses))
    }

    var creates: [Create] { state.withLock(\.creates) }
    var statusRequests: Int { state.withLock(\.statusRequests) }

    func setCreateResult(_ result: Result<Int64, APIError>) { state.withLock { $0.createResult = result } }
    func setStatuses(_ statuses: [Result<VideoServerStatus, APIError>]) { state.withLock { $0.statuses = statuses } }
    func setTemplates(_ result: Result<[VideoTemplate], APIError>) { state.withLock { $0.templates = result } }

    func templates() async throws -> [VideoTemplate] {
        try state.withLock(\.templates).get()
    }

    func createVideo(templateId: Int64, imageJPEG: Data, quality: VideoQuality, duration: Int?) async throws -> Int64 {
        try state.withLock { state in
            state.creates.append(Create(templateId: templateId, imageJPEG: imageJPEG, quality: quality))
            return state.createResult
        }.get()
    }

    func status(serverId: Int64) async throws -> VideoServerStatus {
        try state.withLock { state in
            state.statusRequests += 1
            return state.statuses.count > 1 ? state.statuses.removeFirst() : state.statuses.first ?? .success(.generating)
        }.get()
    }

    static let sampleVideoURL = URL(string: "https://media.pixverse.ai/sample.mp4")!

    static let sampleTemplates: [VideoTemplate] = [
        VideoTemplate(id: 1, name: "Clay Fool", category: "📈 Trending", previewURL: nil,
                      qualities: [.p360, .p540, .p720, .p1080], duration: 5),
        VideoTemplate(id: 2, name: "Dense Snowflakes", category: "💃 Dance", previewURL: nil,
                      qualities: [.p720, .p1080], duration: 5),
        VideoTemplate(id: 3, name: "Warm Light", category: "💛 Warm", previewURL: nil, qualities: [], duration: nil),
    ]
}
#endif
