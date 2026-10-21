import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AIChat

struct DemoVideoAPITests {
    @Test func generatesThenReturnsPlayableLocalVideoWithPhotoProportions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DemoVideoAPI(directory: directory, pendingPolls: 2)

        let id = try await api.createVideo(templateId: 1, imageJPEG: try jpeg(width: 1600, height: 900),
                                           quality: .p1080, duration: nil)

        #expect(try await api.status(serverId: id) == .generating)
        #expect(try await api.status(serverId: id) == .generating)
        guard case let .succeeded(url) = try await api.status(serverId: id) else {
            Issue.record("Ожидали готовое видео")
            return
        }
        #expect(url.isFileURL)
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 720, height: 404))
        #expect(try await asset.load(.duration).seconds > 2)
    }

    @Test func unknownIdIsNotFound() async {
        let api = DemoVideoAPI(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        await #expect(throws: APIError(kind: .notFound)) { _ = try await api.status(serverId: 42) }
    }

    @Test func outputSizeKeepsProportionsWithEvenSides() {
        #expect(FakeVideoRenderer.outputSize(width: 1080, height: 1920, maxSide: 720) == (404, 720))
        #expect(FakeVideoRenderer.outputSize(width: 501, height: 501, maxSide: 720) == (500, 500))
    }

    private func jpeg(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
