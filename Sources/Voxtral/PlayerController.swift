import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class PlayerController {
    private var player: AVPlayer?
    private var timeObserver: Any?

    var currentTime: TimeInterval = 0
    var isPlaying = false
    var duration: TimeInterval = 0
    var rate: Float = 1.0 {
        didSet { if isPlaying { player?.rate = rate } }
    }

    func load(url: URL) {
        unload()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        Task {
            if let d = try? await item.asset.load(.duration) {
                duration = CMTimeGetSeconds(d).isFinite ? CMTimeGetSeconds(d) : 0
            }
        }
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                if let p = self.player, p.timeControlStatus != .playing, self.isPlaying,
                   p.currentItem?.isPlaybackLikelyToKeepUp == false {
                    // buffering; keep state
                }
                if let item = p.currentItem, item.duration.isNumeric,
                   CMTimeGetSeconds(item.duration) - self.currentTime < 0.05 {
                    self.isPlaying = false
                }
            }
        }
    }

    func unload() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        timeObserver = nil
        player?.pause()
        player = nil
        currentTime = 0
        isPlaying = false
        duration = 0
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, duration - currentTime < 0.1 { seek(to: 0) }
            player.rate = rate
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
