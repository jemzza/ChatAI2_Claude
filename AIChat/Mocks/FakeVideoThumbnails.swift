#if DEBUG
import AVFoundation
import Foundation
import UIKit

/// Кадры превью без сети — для `-mockData` и превью: для ссылок (каталог-фейк) —
/// однотонные картинки разных цветов, для локальных файлов (результат `DemoVideoAPI`) —
/// настоящий первый кадр.
struct FakeVideoThumbnails: VideoThumbnailing {
    func thumbnail(for url: URL, maxPixelSize: Int) async -> Data? {
        if url.isFileURL { return await firstFrame(of: url, maxPixelSize: maxPixelSize) }
        let hue = CGFloat(abs(url.absoluteString.hashValue % 360)) / 360
        let size = CGSize(width: 240, height: 320)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.35, brightness: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    private func firstFrame(of url: URL, maxPixelSize: Int) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }
}
#endif
