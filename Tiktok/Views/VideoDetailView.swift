import SwiftUI
import FirebaseAuth

struct VideoDetailView: View {
    @Binding var video: VideoModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var videoService: VideoService
    @State private var showingEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var selectedUserId: String? = nil
    @State private var pushUserProfile = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VideoContent(
                    video: Binding(
                        get: { 
                            // Prioritize VideoService state if available
                            videoService.videos[video.id] ?? video
                        },
                        set: { newValue in
                            video = newValue
                            // Update both caches to maintain consistency
                            videoService.videos[newValue.id] = newValue
                            viewModel.videoCache[newValue.id] = newValue
                        }
                    ),
                    isActive: true,
                    selectedUserId: $selectedUserId,
                    pushUserProfile: $pushUserProfile
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.white, for: .navigationBar)
            .navigationDestination(isPresented: $pushUserProfile) {
                if let userId = selectedUserId {
                    UserProfileView(userId: userId)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.black)
                            .font(.title2)
                    }
                }
                
                // Options button – visible only if the current user owns this video
                if video.userId == Auth.auth().currentUser?.uid {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Edit") {
                                showingEditSheet = true
                            }
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Text("Delete")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(.black)
                                .font(.title2)
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingEditSheet) {
            EditVideoView(video: video) { updatedVideo in
                Task {
                    await viewModel.updateVideo(updatedVideo)
                    video = updatedVideo
                    // Update both caches
                    videoService.videos[updatedVideo.id] = updatedVideo
                    viewModel.videoCache[updatedVideo.id] = updatedVideo
                }
                return true
            }
        }
        .alert("Delete Video", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteVideo(video)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
        .onAppear {
            Task {
                // First fetch the current like state
                let isLiked = await videoService.checkIfVideoIsLiked(videoId: video.id)
                
                // Update the video with the correct like state
                var updatedVideo = video
                updatedVideo.isLiked = isLiked
                
                // Update all state sources atomically
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    video = updatedVideo
                    videoService.videos[video.id] = updatedVideo
                    viewModel.videoCache[video.id] = updatedVideo
                }
                
                // Set up the listener after we have the correct initial state
                videoService.setupVideoListener(videoId: video.id)
            }
        }
        .onDisappear {
            videoService.removeListener(videoId: video.id)
        }
        // Listen for updates from VideoService
        .onChange(of: videoService.videos[video.id]) { _, updatedVideo in
            if let updatedVideo = updatedVideo {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    // Update all state sources atomically
                    video = updatedVideo
                    viewModel.videoCache[updatedVideo.id] = updatedVideo
                }
            }
        }
    }
} 