import Foundation
import AVKit

@MainActor
final class VideoViewModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    private let video: VideoModel
    
    init(video: VideoModel) {
        self.video = video
        setupPlayer()
    }
    
    private func setupPlayer() {
        guard let videoUrl = URL(string: video.videoUrl) else { return }
        let playerItem = AVPlayerItem(url: videoUrl)
        player = AVPlayer(playerItem: playerItem)
    }
    
    func playVideo() {
        player?.play()
    }
    
    func stopVideo() {
        player?.pause()
        player?.seek(to: .zero)
    }
    
    func cleanup() {
        player?.pause()
        player = nil
    }
} 