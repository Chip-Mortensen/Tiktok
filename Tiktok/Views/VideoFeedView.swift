import SwiftUI
import AVKit

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    if viewModel.videos.isEmpty {
                        VStack {
                            Image(systemName: "video.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No videos yet")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    } else {
                        // Custom paging view
                        ScrollViewReader { scrollProxy in
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                                    VideoPlayerView(video: video, isActive: currentIndex == index)
                                        .id(index)
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                }
                            }
                            .offset(y: -CGFloat(currentIndex) * proxy.size.height + dragOffset)
                            .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: currentIndex)
                            .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: dragOffset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Only allow dragging down if not at the top
                                        if value.translation.height > 0 && currentIndex == 0 {
                                            dragOffset = 0
                                        } else {
                                            isDragging = true
                                            dragOffset = value.translation.height
                                        }
                                    }
                                    .onEnded { value in
                                        isDragging = false
                                        let height = proxy.size.height
                                        let dragThreshold = height * 0.2 // 20% of screen height
                                        let predictedEndOffset = value.predictedEndTranslation.height
                                        
                                        if abs(predictedEndOffset) > dragThreshold {
                                            // Only allow swiping up if there are more videos
                                            if predictedEndOffset < 0 && currentIndex < viewModel.videos.count - 1 {
                                                currentIndex += 1
                                                print("Swiped up to next video \(currentIndex)")
                                            }
                                            // Only allow swiping down if not at the top
                                            else if predictedEndOffset > 0 && currentIndex > 0 {
                                                currentIndex -= 1
                                                print("Swiped down to previous video \(currentIndex)")
                                            }
                                        }
                                        
                                        dragOffset = 0
                                    }
                            )
                        }
                    }
                    
                    if viewModel.isLoading {
                        ProgressView()
                    }
                    
                    // Custom navigation bar background
                    VStack {
                        Rectangle()
                            .fill(.white)
                            .frame(height: proxy.safeAreaInsets.top + 44) // Standard nav bar height
                            .ignoresSafeArea()
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("For You")
                        .foregroundColor(.black) // Changed to black for white background
                        .font(.headline)
                }
            }
            .toolbarBackground(.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            print("Fetching initial videos...")
            await viewModel.fetchVideos()
            if !viewModel.videos.isEmpty {
                print("Videos loaded, count: \(viewModel.videos.count)")
                // Force the first video to be active immediately
                currentIndex = 0
                print("Set current index to 0 (top video)")
            }
        }
        .refreshable {
            await viewModel.fetchVideos()
        }
    }
}

struct VideoPlayerView: View {
    let video: VideoModel
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background for letterboxing
                Color.black.edgesIgnoringSafeArea(.all)
                
                // Thumbnail layer
                if let thumbnailUrl = video.thumbnailUrl,
                   let url = URL(string: thumbnailUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit) // Changed to .fit to maintain aspect ratio with black bars
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } placeholder: {
                        Color.black
                    }
                }
                
                // Video player layer
                if let player = player {
                    CustomVideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onTapGesture {
                            if isPlaying {
                                player.pause()
                            } else {
                                player.play()
                            }
                            isPlaying.toggle()
                        }
                }
                
                // Video info overlay
                VStack {
                    Spacer()
                    ZStack {
                        // White background for caption
                        Rectangle()
                            .fill(.white)
                            .frame(height: 60) // Adjust this value as needed
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(video.caption)
                                    .foregroundColor(.black) // Changed to black for white background
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.horizontal)
                            Spacer()
                        }
                    }
                }
            }
            .background(Color.black) // Ensure black background for the entire container
        }
        .onAppear {
            print("VideoPlayerView appeared for video: \(video.id)")
            if isActive {
                setupAndPlay()
            }
        }
        .onChange(of: isActive) { newValue in
            print("Video \(video.id) isActive changed to: \(newValue)")
            if newValue {
                setupAndPlay()
            } else {
                player?.pause()
                isPlaying = false
            }
        }
        .onDisappear {
            print("VideoPlayerView disappeared for video: \(video.id)")
            player?.pause()
            player = nil
            isPlaying = false
        }
    }
    
    private func setupAndPlay() {
        if player == nil, let videoUrl = URL(string: video.videoUrl) {
            print("Creating new player for video: \(video.id)")
            let playerItem = AVPlayerItem(url: videoUrl)
            player = AVPlayer(playerItem: playerItem)
        }
        print("Playing video: \(video.id)")
        player?.play()
        isPlaying = true
    }
}

struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect // Changed to .resizeAspect for proper letterboxing
        
        // Ensure black background
        controller.view.backgroundColor = .black
        controller.view.insetsLayoutMarginsFromSafeArea = false
        
        // Add black background view to ensure letterboxing
        let backgroundView = UIView()
        backgroundView.backgroundColor = .black
        controller.view.insertSubview(backgroundView, at: 0)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: controller.view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ])
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
} 