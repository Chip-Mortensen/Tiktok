import SwiftUI
import FirebaseAuth

struct VideoDetailView: View {
    @Binding var video: VideoModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: ProfileViewModel
    @State private var showingEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var selectedUserId: String? = nil
    @State private var pushUserProfile = false
    
    var body: some View {
        NavigationView {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VideoContent(
                video: $video,
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
    }
} 