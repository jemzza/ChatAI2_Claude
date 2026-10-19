import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Первые кадры видео: память (`NSCache`) → диск (Caches/Thumbnails) → `AVAssetImageGenerator`.
/// Одновременные запросы одного кадра делят одну генерацию.
actor VideoThumbnailService: VideoThumbnailing {
    private let directory: URL
    private let memory = NSCache<NSString, NSData>()
    private var inFlight: [String: Task<Data?, Never>] = [:]

    init(directory: URL) {
        self.directory = directory
        memory.countLimit = 200
    }

    static func standard() -> VideoThumbnailService {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return VideoThumbnailService(directory: caches.appendingPathComponent("Thumbnails", isDirectory: true))
    }

    func thumbnail(for url: URL, maxPixelSize: Int) async -> Data? {
        let key = Self.key(url: url, size: maxPixelSize)
        if let cached = memory.object(forKey: key as NSString) { return cached as Data }
        if let task = inFlight[key] { return await task.value }

        let file = directory.appendingPathComponent("\(key).jpg", isDirectory: false)
        let task = Task.detached(priority: .utility) { () -> Data? in
            if let data = try? Data(contentsOf: file) { return data }
            guard let data = await Self.generate(url: url, maxPixelSize: maxPixelSize) else { return nil }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return data
        }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        if let data { memory.setObject(data as NSData, forKey: key as NSString) }
        return data
    }

    private static func generate(url: URL, maxPixelSize: Int) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let image = try? await generator.image(at: .zero).image else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func key(url: URL, size: Int) -> String {
        let digest = SHA256.hash(data: Data("\(url.absoluteString)#\(size)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
