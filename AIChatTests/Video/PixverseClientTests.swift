import Foundation
import Testing
@testable import AIChat

struct PixverseClientTests {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json"))
    }

    private func client(cacheURL: URL? = nil, _ handler: @escaping StubURLProtocol.Handler) -> (PixverseClient, RequestLog) {
        let (session, log) = StubURLProtocol.session(handler)
        let api = NebulaAPI(client: APIClient(baseURL: URL(string: "https://nebulaapps.site/pixverse")!, session: session),
                            ownerToken: "owner", appID: "com.test.test", userID: { "user-1" })
        return (PixverseClient(api: api, catalogCacheURL: cacheURL), log)
    }

    @Test func decodesRealTemplatesCatalog() async throws {
        let body = try fixture("pixverse_templates")
        let (client, log) = client { _ in .response(status: 200, body: body) }

        let templates = try await client.templates()

        #expect(log.all.first?.url?.path == "/pixverse/api/v1/get_templates/com.test.test")
        #expect(templates.count == 4)
        let first = try #require(templates.first)
        #expect(first.id == 374_743_997_109_542)
        #expect(first.name == "Dense Snowflakes")
        #expect(first.category == "📈 Trending")
        #expect(first.previewURL?.pathExtension == "mp4")
        #expect(first.qualities == [.p360, .p540, .p720, .p1080])
        #expect(first.duration == 5)
    }

    @Test func inactiveTemplatesAreSkipped() throws {
        let json = #"{"templates":[{"template_id":1,"name":"On","is_active":1},{"template_id":2,"name":"Off","is_active":0}]}"#
        #expect(try PixverseClient.decodeTemplates(Data(json.utf8)).map(\.name) == ["On"])
    }

    @Test func offlineFallsBackToCachedCatalog() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let body = try fixture("pixverse_templates")
        let online = Locked(true)
        let (client, _) = client(cacheURL: cacheURL) { _ in
            online.withLock { $0 } ? .response(status: 200, body: body) : .failure(.notConnectedToInternet)
        }

        let fresh = try await client.templates()
        online.withLock { $0 = false }
        let cached = try await client.templates()

        #expect(cached == fresh)
    }

    @Test func offlineWithoutCacheFails() async {
        let (client, _) = client { _ in .failure(.notConnectedToInternet) }
        await #expect(throws: APIError(kind: .offline)) { _ = try await client.templates() }
    }

    @Test func createSendsMultipartAndReturnsVideoId() async throws {
        let body = try fixture("pixverse_template2video")
        let (client, log) = client { _ in .response(status: 201, body: body) }

        let id = try await client.createVideo(templateId: 374_743_997_109_542, imageJPEG: Data([0xFF, 0xD8]),
                                              quality: .p720, duration: 5)

        #expect(id == 900_001)
        let request = try #require(log.all.first)
        #expect(request.url?.path == "/pixverse/api/v1/template2video")
        let text = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(text.contains("name=\"template_id\"\r\n\r\n374743997109542\r\n"))
        #expect(text.contains("name=\"quality\"\r\n\r\n720p\r\n"))
        #expect(text.contains("name=\"duration\"\r\n\r\n5\r\n"))
        #expect(text.contains("name=\"image\"; filename=\"photo.jpg\""))
    }

    @Test func statusMapsServerStates() async throws {
        let success = try fixture("pixverse_status_success")
        let replies = Locked<[Data]>([
            Data(#"{"status":"generating","video_url":null}"#.utf8),
            success,
            Data(#"{"status":"error","video_url":null}"#.utf8),
        ])
        let (client, log) = client { _ in .response(status: 200, body: replies.withLock { $0.removeFirst() }) }

        #expect(try await client.status(serverId: 900_001) == .generating)
        #expect(try await client.status(serverId: 900_001) == .succeeded(URL(string:
            "https://media.pixverse.ai/pixverse%2Fmp4%2Fmedia%2Fweb%2Fori%2Fbe05a3dc-a615-4274-99cc-85d39d5d5619_seed0.mp4")!))
        #expect(try await client.status(serverId: 900_001) == .failed)
        #expect(log.all.first?.url?.query == "id=900001&user_id=user-1&app_id=com.test.test")
    }

    @Test func unknownGenerationIsNotFound() async throws {
        let body = try fixture("pixverse_status_not_found")
        let (client, _) = client { _ in .response(status: 404, body: body) }
        await #expect(throws: APIError(kind: .notFound)) { _ = try await client.status(serverId: 1) }
    }
}
