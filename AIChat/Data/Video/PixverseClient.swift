import Foundation

/// `VideoAPI` на PixVerse v1 (контракты — docs/task.md).
struct PixverseClient: VideoAPI {
    let api: NebulaAPI
    /// Куда сохранять последний каталог шаблонов (для работы без сети); `nil` — не сохранять.
    let catalogCacheURL: URL?

    // MARK: Шаблоны

    private struct Catalog: Decodable {
        let templates: [Template]
    }

    private struct Template: Decodable {
        let templateId: Int64
        let name: String
        let category: String?
        let duration: Int?
        let previewSmall: String?
        let previewLarge: String?
        let qualities: [String]?
        let isActive: FlexibleBool?
    }

    /// `is_active` приходит числом (0/1); на всякий случай принимаем и `Bool`.
    private struct FlexibleBool: Decodable {
        let value: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                value = bool
            } else {
                value = try container.decode(Int.self) != 0
            }
        }
    }

    func templates() async throws -> [VideoTemplate] {
        let data: Data
        do {
            data = try await api.data(for: .get("api/v1/get_templates/\(api.appID)"))
            if let catalogCacheURL { try? data.write(to: catalogCacheURL, options: .atomic) }
        } catch let error as APIError where error.kind == .offline {
            guard let catalogCacheURL, let cached = try? Data(contentsOf: catalogCacheURL) else { throw error }
            data = cached
        }
        return try Self.decodeTemplates(data)
    }

    static func decodeTemplates(_ data: Data) throws -> [VideoTemplate] {
        let catalog: Catalog
        do {
            catalog = try APIClient.decoder.decode(Catalog.self, from: data)
        } catch {
            throw APIError(kind: .decoding)
        }
        return catalog.templates
            .filter { $0.isActive?.value ?? true }
            .map { template in
                VideoTemplate(
                    id: template.templateId,
                    name: template.name,
                    category: template.category ?? "",
                    previewURL: (template.previewSmall ?? template.previewLarge).flatMap(URL.init(string:)),
                    qualities: (template.qualities ?? []).compactMap(VideoQuality.init(rawValue:)),
                    duration: template.duration
                )
            }
    }

    // MARK: Генерация

    private struct CreateResponse: Decodable {
        let videoId: Int64
    }

    private struct StatusResponse: Decodable {
        let status: String
        let videoUrl: String?
    }

    func createVideo(templateId: Int64, imageJPEG: Data, quality: VideoQuality, duration: Int?) async throws -> Int64 {
        var form = MultipartFormData()
        form.append(String(templateId), name: "template_id")
        form.append(quality.rawValue, name: "quality")
        if let duration { form.append(String(duration), name: "duration") }
        form.append(imageJPEG, name: "image", fileName: "photo.jpg", mimeType: "image/jpeg")
        let response: CreateResponse = try await api.send(.post("api/v1/template2video", multipart: form))
        return response.videoId
    }

    func status(serverId: Int64) async throws -> VideoServerStatus {
        let response: StatusResponse = try await api.send(
            .get("api/v1/status", query: [URLQueryItem(name: "id", value: String(serverId))])
        )
        switch response.status {
        case "success":
            guard let url = response.videoUrl.flatMap(URL.init(string:)) else { throw APIError(kind: .decoding) }
            return .succeeded(url)
        case "error":
            return .failed
        default:
            // `generating` и всё, чего мы не знаем, — ждём дальше.
            return .generating
        }
    }
}
