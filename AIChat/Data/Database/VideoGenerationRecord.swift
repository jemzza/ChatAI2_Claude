import Foundation
import GRDB

/// Строка таблицы `videoGeneration`.
struct VideoGenerationRecord: Codable, Hashable, Sendable {
    static let databaseTableName = "videoGeneration"

    var id: UUID
    var templateId: Int64
    var templateName: String
    var aspect: String
    var quality: String
    var sourceImageName: String
    var status: String
    var serverId: Int64?
    var videoURL: String?
    var localVideoName: String?
    var failureKind: String?
    var failureRetryAt: Date?
    var isViewed: Bool
    var createdAt: Date

    enum Columns {
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

extension VideoGenerationRecord: FetchableRecord, PersistableRecord {
    // См. `ChatRecord`: даты храним числом, без потери точности.
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

extension VideoGenerationRecord {
    init(_ generation: VideoGeneration) {
        id = generation.id
        templateId = generation.templateId
        templateName = generation.templateName
        aspect = generation.aspect.rawValue
        quality = generation.quality.rawValue
        sourceImageName = generation.sourceImageName
        status = generation.status.rawValue
        serverId = generation.serverId
        videoURL = generation.videoURL?.absoluteString
        localVideoName = generation.localVideoName
        failureKind = generation.failure?.kind.rawValue
        failureRetryAt = generation.failure?.retryAt
        isViewed = generation.isViewed
        createdAt = generation.createdAt
    }

    /// - Throws: `InvalidDatabaseValue`, если в базе неизвестные формат, качество или статус.
    func generation() throws -> VideoGeneration {
        guard let aspect = VideoAspect(rawValue: aspect) else {
            throw InvalidDatabaseValue(column: "aspect", value: aspect)
        }
        guard let quality = VideoQuality(rawValue: quality) else {
            throw InvalidDatabaseValue(column: "quality", value: quality)
        }
        guard let status = VideoGenerationStatus(rawValue: status) else {
            throw InvalidDatabaseValue(column: "status", value: status)
        }
        // Неизвестный вид ошибки (например, из будущей версии) — `unknown`, а не сбой чтения.
        let failure = failureKind.map { MessageFailure(kind: ErrorKind(rawValue: $0) ?? .unknown, retryAt: failureRetryAt) }
        return VideoGeneration(
            id: id, templateId: templateId, templateName: templateName, aspect: aspect, quality: quality,
            sourceImageName: sourceImageName, status: status, serverId: serverId,
            videoURL: videoURL.flatMap(URL.init(string:)), localVideoName: localVideoName,
            failure: failure, isViewed: isViewed, createdAt: createdAt
        )
    }

    static func newestFirst() -> QueryInterfaceRequest<VideoGenerationRecord> {
        order(Columns.createdAt.desc, Column.rowID.desc)
    }
}
