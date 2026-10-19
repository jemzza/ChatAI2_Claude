import AVFoundation
import SwiftUI
import UIKit

/// Видео по кругу без системных контролов: превью шаблона и результат генерации.
/// `isPlaying == false` — пауза. Плеер освобождается вместе с view.
struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    var isPlaying = true
    var isMuted = true
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.configure(url: url, gravity: gravity)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.url != url { view.configure(url: url, gravity: gravity) }
        view.player.isMuted = isMuted
        if isPlaying { view.player.play() } else { view.player.pause() }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.player.pause()
        view.player.removeAllItems()
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        let player = AVQueuePlayer()
        private(set) var url: URL?
        private var looper: AVPlayerLooper?

        private var playerLayer: AVPlayerLayer {
            // `layerClass` гарантирует тип слоя.
            layer as? AVPlayerLayer ?? AVPlayerLayer()
        }

        func configure(url: URL, gravity: AVLayerVideoGravity) {
            self.url = url
            playerLayer.player = player
            playerLayer.videoGravity = gravity
            player.removeAllItems()
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
    }
}
