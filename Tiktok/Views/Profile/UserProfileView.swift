import SwiftUI
import FirebaseAuth

struct UserProfileView: View {
    let userId: String
    @StateObject private var viewModel = UserProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.primary)
                        .imageScale(.large)
                }
                
                Spacer()
                
                Text(viewModel.user?.username ?? "Profile")
                    .font(.headline)
                
                Spacer()
                
                // Placeholder for symmetry
                Image(systemName: "chevron.left")
                    .foregroundColor(.clear)
                    .imageScale(.large)
            }
            .padding()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Header
                    VStack(spacing: 12) {
                        // Profile Image
                        if let profileImageUrl = viewModel.user?.profileImageUrl {
                            AsyncImage(url: URL(string: profileImageUrl)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundColor(.gray)
                                .frame(width: 96, height: 96)
                        }
                        
                        // Username
                        Text("@\(viewModel.user?.username ?? "")")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        // Bio
                        if let bio = viewModel.user?.bio {
                            Text(bio)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Follow Button
                        if viewModel.user?.id != Auth.auth().currentUser?.uid {
                            Button {
                                Task {
                                    await viewModel.toggleFollow()
                                }
                            } label: {
                                Text(viewModel.isFollowing ? "Following" : "Follow")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(viewModel.isFollowing ? .primary : .white)
                                    .frame(width: 160, height: 44)
                                    .background(viewModel.isFollowing ? Color.gray.opacity(0.1) : Color.blue)
                                    .cornerRadius(22)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: viewModel.isFollowing ? 1 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.top)
                    
                    // Stats Row
                    HStack(spacing: 32) {
                        VStack {
                            Text("\(viewModel.user?.postsCount ?? 0)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Posts")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(viewModel.user?.followersCount ?? 0)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Followers")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(viewModel.user?.followingCount ?? 0)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Following")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical)
                    
                    // Videos Grid
                    UserVideosGridView(viewModel: viewModel)
                }
            }
        }
        .task {
            await viewModel.loadUserProfile(userId: userId)
        }
    }
}

// Helper struct for video grid with detail view
struct UserVideosGridView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @State private var selectedVideoIndex: Int?
    
    var body: some View {
        VideoGridView(
            videos: .constant(viewModel.userVideos),
            onVideoTap: { video in
                if let index = viewModel.userVideos.firstIndex(where: { $0.id == video.id }) {
                    selectedVideoIndex = index
                }
            }
        )
        .sheet(item: Binding(
            get: { selectedVideoIndex.map { Index(int: $0) } },
            set: { selectedVideoIndex = $0?.int }
        )) { index in
            if let video = viewModel.userVideos[safe: index.int] {
                VideoDetailView(video: .constant(video))
            }
        }
    }
}

// Helper struct to make Int identifiable for sheet presentation
private struct Index: Identifiable {
    let int: Int
    var id: Int { int }
} 