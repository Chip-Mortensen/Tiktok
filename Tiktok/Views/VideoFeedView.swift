import SwiftUI
import AVKit

// MARK: - Navigation Bar Styling
struct NavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("For You")
                        .foregroundColor(.black)
                        .font(.headline)
                }
            }
            .toolbarBackground(.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func customNavigationBar() -> some View {
        self.modifier(NavigationBarModifier())
    }
}

// MARK: - Main View
struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var currentIndex: Int = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Base black background
                Color.black.edgesIgnoringSafeArea(.all)
                
                if viewModel.videos.isEmpty {
                    // Empty state
                    VStack {
                        Image(systemName: "video.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No videos yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                } else {
                    // Video pager will go here
                    VideoPager(
                        videos: viewModel.videos,
                        currentIndex: $currentIndex
                    )
                }
            }
            .customNavigationBar()
        }
        .task {
            await viewModel.fetchVideos()
        }
        .refreshable {
            await viewModel.fetchVideos()
        }
    }
}

// MARK: - Video Pager
struct VideoPager: View {
    let videos: [VideoModel]
    @Binding var currentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                // Stack of videos
                VStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        VideoPlayerContainer(
                            video: video,
                            isActive: currentIndex == index
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .offset(y: -CGFloat(currentIndex) * geometry.size.height + dragOffset)
                .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
                .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Prevent dragging down at the top
                            if value.translation.height > 0 && currentIndex == 0 {
                                let dampedOffset = value.translation.height / 3 // Add resistance
                                dragOffset = dampedOffset
                            }
                            // Prevent dragging up at the bottom
                            else if value.translation.height < 0 && currentIndex == videos.count - 1 {
                                let dampedOffset = value.translation.height / 3 // Add resistance
                                dragOffset = dampedOffset
                            }
                            // Normal dragging
                            else {
                                isDragging = true
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            isDragging = false
                            
                            // Calculate velocity and threshold
                            let velocity = value.predictedEndTranslation.height - value.translation.height
                            let threshold = geometry.size.height * 0.2 // 20% threshold for swipe
                            
                            // Determine if we should change index based on drag distance or velocity
                            if abs(value.translation.height) > threshold || abs(velocity) > 500 {
                                if value.translation.height < 0 && currentIndex < videos.count - 1 {
                                    // Swipe up to next video
                                    currentIndex += 1
                                } else if value.translation.height > 0 && currentIndex > 0 {
                                    // Swipe down to previous video
                                    currentIndex -= 1
                                }
                            }
                            
                            // Reset drag offset with animation
                            dragOffset = 0
                        }
                )
            }
            .clipped() // Ensure only one video is visible at a time
        }
    }
}

// MARK: - Array Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Video Player Container
struct VideoPlayerContainer: View {
    let video: VideoModel
    let isActive: Bool
    
    var body: some View {
        GeometryReader { geometry in
            VideoContent(video: video, isActive: isActive)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped() // Ensure content is cropped if it overflows
        }
    }
}

// MARK: - Video Content
struct VideoContent: View {
    let video: VideoModel
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                CustomVideoPlayer(player: player)
                    .onTapGesture {
                        if isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isPlaying.toggle()
                    }
            } else if let thumbnailUrl = video.thumbnailUrl,
                      let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill) // Fill available space
                        .clipped()
                } placeholder: {
                    Color.black
                }
            }
        }
        .onAppear {
            if isActive {
                setupAndPlay()
            }
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                setupAndPlay()
            } else {
                player?.pause()
                isPlaying = false
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            isPlaying = false
        }
    }
    
    private func setupAndPlay() {
        if player == nil, let videoUrl = URL(string: video.videoUrl) {
            let playerItem = AVPlayerItem(url: videoUrl)
            player = AVPlayer(playerItem: playerItem)
        }
        player?.play()
        isPlaying = true
    }
}

// MARK: - Custom Video Player
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill // This ensures the video fills width and crops height if needed
        controller.view.backgroundColor = .black
        
        // Remove any default margins or insets
        controller.view.insetsLayoutMarginsFromSafeArea = false
        controller.view.layoutMargins = .zero
        
        if let playerLayer = controller.view.layer.sublayers?.first {
            playerLayer.frame = controller.view.bounds
            playerLayer.masksToBounds = true
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
} 