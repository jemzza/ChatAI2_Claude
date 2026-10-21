import SwiftUI
import UIKit

/// Первый кадр видео по ссылке; пока грузится — тёмная подложка.
struct VideoThumbnailView: View {
    let url: URL?
    let thumbnails: any VideoThumbnailing
    var maxPixelSize = 480

    @State private var image: UIImage?

    var body: some View {
        // Картинка — в overlay: размер задаёт фон (сколько предложили), а `scaledToFill`
        // внутри ZStack растянул бы карточку шире колонки.
        Color.appSurface
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
        .task(id: url) {
            guard let url, image == nil else { return }
            let data = await thumbnails.thumbnail(for: url, maxPixelSize: maxPixelSize)
            // Декодируем вне главного потока: UIImage(data:) не дешёвый для сетки из сотен карточек.
            let decoded = await Task.detached(priority: .userInitiated) {
                data.flatMap { UIImage(data: $0)?.preparingForDisplay() }
            }.value
            withAnimation(.easeOut(duration: 0.25)) { image = decoded }
        }
    }
}
