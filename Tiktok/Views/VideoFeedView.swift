import SwiftUI
import AVKit
import FirebaseAuth
import FirebaseFirestore

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
    @StateObject private var profileViewModel = ProfileViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var currentIndex: Int = 0
    @State private var showingComments = false
    @State private var selectedUserId: String? = nil
    @State private var pushUserProfile = false
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationStack {
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
                    VideoPager(
                        videos: $viewModel.videos,
                        currentIndex: $currentIndex,
                        selectedUserId: $selectedUserId,
                        pushUserProfile: $pushUserProfile
                    )
                    .environmentObject(viewModel)
                    .environmentObject(profileViewModel)
                    .environmentObject(appState)
                }
            }
            .customNavigationBar()
            .navigationDestination(isPresented: $pushUserProfile) {
                if let userId = selectedUserId {
                    UserProfileView(userId: userId)
                }
            }
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
    @Binding var videos: [VideoModel]
    @Binding var currentIndex: Int
    @Binding var selectedUserId: String?
    @Binding var pushUserProfile: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                // Stack of videos
                VStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, _ in
                        VideoPlayerContainer(
                            video: $videos[index],
                            isActive: currentIndex == index,
                            selectedUserId: $selectedUserId,
                            pushUserProfile: $pushUserProfile
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .offset(y: -CGFloat(currentIndex) * geometry.size.height)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            isDragging = false
                            dragOffset = 0
                            
                            let height = geometry.size.height
                            let dragThreshold = height * 0.2
                            let draggedDistance = value.translation.height
                            let predictedEndLocation = value.predictedEndLocation.y
                            
                            if abs(draggedDistance) > dragThreshold || abs(predictedEndLocation) > dragThreshold {
                                let newIndex = draggedDistance > 0 ? currentIndex - 1 : currentIndex + 1
                                if newIndex >= 0 && newIndex < videos.count {
                                    withAnimation {
                                        currentIndex = newIndex
                                    }
                                }
                            }
                        }
                )
            }
        }
    }
}

// MARK: - Video Player Container
struct VideoPlayerContainer: View {
    @Binding var video: VideoModel
    let isActive: Bool
    @Binding var selectedUserId: String?
    @Binding var pushUserProfile: Bool
    @EnvironmentObject private var viewModel: VideoFeedViewModel
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var videoService: VideoService
    
    var body: some View {
        GeometryReader { geometry in
            VideoContent(
                video: $video,
                isActive: isActive,
                selectedUserId: $selectedUserId,
                pushUserProfile: $pushUserProfile
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .environmentObject(viewModel)
            .environmentObject(appState)
            .environmentObject(videoService)
        }
    }
}

// MARK: - Video Content
struct VideoContent: View {
    @Binding var video: VideoModel
    let isActive: Bool
    @Binding var selectedUserId: String?
    @Binding var pushUserProfile: Bool
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var videoService: VideoService
    @State private var showingComments = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabSelection) private var tabSelection
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                CustomVideoPlayer(player: player)
                    .gesture(
                        TapGesture()
                            .onEnded { _ in
                                // Only handle mute toggle if not interacting with other UI elements
                                if !pushUserProfile {
                                    appState.isMuted.toggle()
                                }
                            }
                    )
            } else if let thumbnailUrl = video.thumbnailUrl,
                      let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } placeholder: {
                    Color.black
                }
            }
            
            // Action buttons overlay
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    // Video info (left side)
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            print("DEBUG: Username tapped for: \(video.username ?? "unknown")")
                            player?.pause()
                            isPlaying = false
                            
                            if video.userId == Auth.auth().currentUser?.uid {
                                // It's the current user: switch tab
                                dismiss()
                                tabSelection.wrappedValue = 3  // Profile tab
                            } else {
                                // For another user, set the state to push the profile view
                                selectedUserId = video.userId
                                pushUserProfile = true
                            }
                        } label: {
                            Text("@\(video.username ?? "user")")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text(video.caption)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 60)
                    
                    // Action buttons (right side)
                    VStack(spacing: 20) {
                        // Like Button
                        Button {
                            Task {
                                await videoService.toggleLike(for: video.id)
                                if let updatedVideo = videoService.videos[video.id] {
                                    video = updatedVideo
                                }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: video.isLiked ? "heart.fill" : "heart")
                                    .font(.title)
                                    .foregroundColor(video.isLiked ? .red : .white)
                                    .scaleEffect(video.isLiked ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: video.isLiked)
                                Text("\(video.likes)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Comment Button
                        Button {
                            showingComments = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.right")
                                    .font(.title)
                                    .foregroundColor(.white)
                                Text("\(video.commentsCount)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Bookmark Button (placeholder)
                        Button {
                            // TODO: Implement bookmarks
                        } label: {
                            Image(systemName: "bookmark")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        // Sound indicator
                        Image(systemName: appState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(.top, 10)
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(viewModel: CommentsViewModel(videoId: video.id))
        }
        .onAppear {
            if isActive {
                setupAndPlay()
                videoService.setupVideoListener(videoId: video.id)
                videoService.videos[video.id] = video
            }
        }
        .onChange(of: isActive) { wasActive, isNowActive in
            if isNowActive {
                setupAndPlay()
                videoService.setupVideoListener(videoId: video.id)
            } else {
                player?.pause()
                isPlaying = false
                videoService.removeListener(videoId: video.id)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            isPlaying = false
            videoService.removeListener(videoId: video.id)
        }
        .onChange(of: appState.isMuted) { _, isMuted in
            // Update player mute state whenever global state changes
            player?.isMuted = isMuted
        }
    }
    
    private func setupAndPlay() {
        if player == nil {
            let videoUrl: URL?
            if let m3u8UrlString = video.m3u8Url {
                videoUrl = URL(string: m3u8UrlString)
            } else {
                videoUrl = URL(string: video.videoUrl)
            }
            
            if let videoUrl = videoUrl {
                // Create an asset with an optimized loading configuration
                let asset = AVURLAsset(url: videoUrl, options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true,
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "User-Agent": "TikTok-iOS"
                    ]
                ])
                
                // Create a player item with automatic buffering
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 8.0 // Buffer 8 seconds ahead
                
                // Create player immediately for UI purposes
                player = AVPlayer(playerItem: playerItem)
                player?.automaticallyWaitsToMinimizeStalling = true
                player?.isMuted = appState.isMuted
                
                // Set up looping
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { [weak player] _ in
                    player?.seek(to: .zero)
                    player?.play()
                }
                
                // Load the asset asynchronously
                Task {
                    do {
                        let isPlayable = try await asset.load(.isPlayable)
                        if isPlayable {
                            await MainActor.run {
                                // Start playing once ready
                                self.player?.play()
                                self.isPlaying = true
                            }
                        }
                    } catch {
                        print("Failed to load asset: \(error)")
                    }
                }
            }
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