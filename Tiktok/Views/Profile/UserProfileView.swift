import SwiftUI
import FirebaseAuth

struct UserProfileView: View {
    let userId: String
    @StateObject private var viewModel = UserProfileViewModel()
    @State private var activeSheet: UserListSheetType?
    
    var body: some View {
        VStack(spacing: 0) {
            // Profile Header
            VStack(spacing: 16) {
                // Profile Image
                if let profileImageUrl = viewModel.user?.profileImageUrl {
                    AsyncImage(url: URL(string: profileImageUrl)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 96, height: 96)
                }
                
                // Username
                Text(viewModel.user?.username ?? "")
                    .font(.headline)
                
                // Stats Row
                HStack(spacing: 32) {
                    StatColumn(count: viewModel.user?.followingCount ?? 0, 
                             title: "Following",
                             action: { activeSheet = .following })
                    
                    StatColumn(count: viewModel.user?.followersCount ?? 0, 
                             title: "Followers",
                             action: { activeSheet = .followers })
                    
                    StatColumn(count: viewModel.user?.likesCount ?? 0, 
                             title: "Likes",
                             isEnabled: userId == Auth.auth().currentUser?.uid,
                             action: { 
                                if userId == Auth.auth().currentUser?.uid {
                                    activeSheet = .likes
                                }
                             })
                }
                
                // Bio
                if let bio = viewModel.user?.bio {
                    Text(bio)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Follow Button (only show for other users)
                if userId != Auth.auth().currentUser?.uid {
                    Button {
                        Task {
                            await viewModel.toggleFollow()
                        }
                    } label: {
                        Text(viewModel.isFollowing ? "Following" : "Follow")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(width: 120, height: 32)
                            .background(viewModel.isFollowing ? Color.gray.opacity(0.1) : Color.blue)
                            .foregroundColor(viewModel.isFollowing ? .primary : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(.vertical)
            .padding(.horizontal)
            
            // Videos Grid
            UserVideosGridView(viewModel: viewModel)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(viewModel.user?.username ?? "Profile")
        .sheet(item: $activeSheet) { sheetType in
            UserListSheetView(sheetType: sheetType, userId: userId)
        }
        .task {
            await viewModel.loadUserProfile(userId: userId)
        }
    }
}

// Helper struct for video grid with detail view
struct UserVideosGridView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var selectedVideo: VideoModel?
    
    var body: some View {
        VideoGridView(
            videos: .constant(viewModel.userVideos),
            onVideoTap: { video in
                selectedVideo = video
            }
        )
        .navigationDestination(item: $selectedVideo) { video in
            VideoDetailView(video: Binding(
                get: { video },
                set: { newValue in
                    // Update the video in the userVideos array
                    if let idx = viewModel.userVideos.firstIndex(where: { $0.id == newValue.id }) {
                        viewModel.userVideos[idx] = newValue
                    }
                    selectedVideo = newValue
                }
            ))
            .environmentObject(profileViewModel)
        }
        .task {
            await profileViewModel.fetchUserData()
        }
    }
}

// Helper struct to make Int identifiable for sheet presentation
private struct Index: Identifiable {
    let int: Int
    var id: Int { int }
} 