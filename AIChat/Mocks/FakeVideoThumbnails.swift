#if DEBUG
import Foundation
import UIKit

/// Кадры превью без сети: однотонные картинки разных цветов (по ссылке) — для `-mockData` и превью.
struct FakeVideoThumbnails: VideoThumbnailing {
    func thumbnail(for url: URL, maxPixelSize: Int) async -> Data? {
        let hue = CGFloat(abs(url.absoluteString.hashValue % 360)) / 360
        let size = CGSize(width: 240, height: 320)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.35, brightness: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
#endif
