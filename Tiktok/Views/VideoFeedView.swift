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
    @State private var showingProfile = false
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    
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
                    VideoPager(
                        videos: $viewModel.videos,
                        currentIndex: $currentIndex
                    )
                    .environmentObject(profileViewModel)
                    .environmentObject(appState)
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
    @Binding var videos: [VideoModel]
    @Binding var currentIndex: Int
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
                            isActive: currentIndex == index
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
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        GeometryReader { geometry in
            VideoContent(video: $video, isActive: isActive)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .environmentObject(profileViewModel)
                .environmentObject(appState)
        }
    }
}

// MARK: - Video Content
struct VideoContent: View {
    @Binding var video: VideoModel
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @EnvironmentObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showingProfile = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabSelection) private var tabSelection
    @State private var showingComments = false
    private let firestoreService = FirestoreService.shared
    @State private var videoListener: ListenerRegistration?
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                CustomVideoPlayer(player: player)
                    .gesture(
                        TapGesture()
                            .onEnded { _ in
                                // Only handle mute toggle if not interacting with other UI elements
                                if !showingProfile {
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
                            print("DEBUG: Username tapped, showing profile for: \(video.username ?? "unknown")")
                            player?.pause()
                            isPlaying = false
                            
                            if video.userId == Auth.auth().currentUser?.uid {
                                // If it's the current user's video, switch to profile tab
                                dismiss()
                                tabSelection.wrappedValue = 2 // Profile tab
                            } else {
                                // If it's another user's video, show profile sheet
                                showingProfile = true
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
                                if video.isLiked {
                                    await viewModel.unlikeVideo(video.id)
                                    video.unlike()
                                } else {
                                    await viewModel.likeVideo(video.id)
                                    video.like()
                                }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: video.isLiked ? "heart.fill" : "heart")
                                    .font(.title)
                                    .foregroundColor(video.isLiked ? .red : .white)
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
        .onChange(of: showingProfile) { _, isShowing in
            print("DEBUG: Profile sheet state changed - isShowing: \(isShowing)")
            if isShowing {
                player?.pause()
                isPlaying = false
            } else if isActive {
                player?.play()
                isPlaying = true
            }
        }
        .sheet(isPresented: $showingProfile) {
            NavigationView {
                UserProfileView(userId: video.userId)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(viewModel: CommentsViewModel(videoId: video.id))
        }
        .onAppear {
            if isActive {
                setupAndPlay()
                setupVideoListener()
            }
            // Check if video is liked when view appears
            Task {
                video.isLiked = await viewModel.isVideoLiked(video)
            }
        }
        .onChange(of: isActive) { wasActive, isNowActive in
            if isNowActive {
                setupAndPlay()
                setupVideoListener()
            } else {
                player?.pause()
                isPlaying = false
                videoListener?.remove()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            isPlaying = false
            videoListener?.remove()
        }
        .onChange(of: appState.isMuted) { _, isMuted in
            // Update player mute state whenever global state changes
            player?.isMuted = isMuted
        }
    }
    
    private func setupAndPlay() {
        if player == nil, let videoUrl = URL(string: video.videoUrl) {
            let playerItem = AVPlayerItem(url: videoUrl)
            player = AVPlayer(playerItem: playerItem)
            
            // Set up looping
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            
            // Set initial mute state
            player?.isMuted = appState.isMuted
        }
        player?.play()
        isPlaying = true
    }
    
    private func setupVideoListener() {
        videoListener?.remove()
        videoListener = firestoreService.addVideoListener(videoId: video.id) { updatedVideo in
            if let updatedVideo = updatedVideo {
                // Preserve the isLiked state when updating
                let wasLiked = video.isLiked
                video = updatedVideo
                video.isLiked = wasLiked
            }
        }
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