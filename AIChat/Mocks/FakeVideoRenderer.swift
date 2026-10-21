#if DEBUG
import AVFoundation
import CoreGraphics
import ImageIO

/// Рендерит из фото короткое mp4 с медленным наездом — «результат» генерации
/// в `-mockData`: экран результата, Download и Share работают без сети.
enum FakeVideoRenderer {
    enum Failure: Error {
        case badImage
        case writer
    }

    /// Синхронно (кадры пишутся в цикле) — вызывать не с главного потока.
    static func render(jpeg: Data, to url: URL, seconds: Double = 3, fps: Int32 = 24) throws {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.badImage }
        let size = outputSize(width: image.width, height: image.height, maxSide: 720)

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ])
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.writer }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(seconds * Double(fps))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw Failure.writer }
            draw(image, into: buffer, zoom: 1 + 0.12 * Double(frame) / Double(frames))
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            else { throw Failure.writer }
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else { throw Failure.writer }
    }

    /// Пропорции фото, длинная сторона не больше `maxSide`, стороны чётные (H.264).
    static func outputSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        let scale = min(1, Double(maxSide) / Double(max(width, height, 1)))
        func even(_ value: Int) -> Int { max(2, Int((Double(value) * scale).rounded()) / 2 * 2) }
        return (even(width), even(height))
    }

    private static func draw(_ image: CGImage, into buffer: CVPixelBuffer, zoom: Double) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return }
        // Заполнение кадра с наездом от центра.
        let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height)) * zoom
        let drawn = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        let origin = CGPoint(x: (Double(width) - drawn.width) / 2, y: (Double(height) - drawn.height) / 2)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: origin, size: drawn))
    }
}
#endif
