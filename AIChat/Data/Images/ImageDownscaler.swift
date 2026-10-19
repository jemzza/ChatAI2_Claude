import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Готовит фото к отправке: уменьшает до `maxPixelSize` по длинной стороне и пережимает в JPEG.
/// Метаданные (EXIF, геопозиция) не переносятся — в базу и в сеть уходят только пиксели.
enum ImageDownscaler {
    /// Хватает vision-модели и держит вложение в базе в пределах ~100–300 KB.
    static let maxPixelSize = 1024
    static let jpegQuality = 0.7

    /// - Returns: JPEG или `nil`, если это не картинка (или её не удалось прочитать).
    static func jpeg(from data: Data) -> Data? {
        thumbnail(from: data, maxPixelSize: maxPixelSize).flatMap(encode)
    }

    /// Центральный кроп под соотношение `aspect` (ширина / высота) и уменьшение
    /// длинной стороны до `maxPixelSize`. Для фото к генерации видео.
    /// - Returns: JPEG или `nil`, если это не картинка.
    static func jpeg(from data: Data, croppedTo aspect: Double, maxPixelSize: Int) -> Data? {
        guard aspect > 0, let image = thumbnail(from: data, maxPixelSize: maxPixelSize) else { return nil }
        let width = Double(image.width)
        let height = Double(image.height)
        var crop = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > aspect {
            crop.size.width = (height * aspect).rounded()
            crop.origin.x = ((width - crop.width) / 2).rounded(.down)
        } else {
            crop.size.height = (width / aspect).rounded()
            crop.origin.y = ((height - crop.height) / 2).rounded(.down)
        }
        return image.cropping(to: crop).flatMap(encode)
    }

    private static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Учитываем ориентацию из EXIF — иначе фото с камеры лягут на бок.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
