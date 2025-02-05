import SwiftUI
import FirebaseAuth

struct UserListSheetView: View {
    let sheetType: UserListSheetType
    let userId: String
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UserListViewModel()
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading \(sheetType.title)...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.users.isEmpty && viewModel.likes.isEmpty {
                    Text("No \(sheetType.title.lowercased()) found")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        switch sheetType {
                        case .followers, .following:
                            ForEach(viewModel.users) { user in
                                UserRowView(user: user)
                            }
                        case .likes:
                            ForEach(viewModel.likes) { like in
                                HStack(spacing: 12) {
                                    // Profile Image
                                    if let profileImageUrl = like.profileImageUrl,
                                       let url = URL(string: profileImageUrl) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Circle()
                                                .fill(Color.gray.opacity(0.3))
                                        }
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 50, height: 50)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        // Username
                                        Text("@\(like.username ?? "user")")
                                            .font(.headline)
                                        
                                        // Timestamp
                                        Text(like.timestamp.formatted(.relative(presentation: .named)))
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle(sheetType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadUsers(userId: userId, sheetType: sheetType)
            }
        }
    }
}

@MainActor
class UserListViewModel: ObservableObject {
    @Published var users: [UserModel] = []
    @Published var likes: [LikeModel] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firestoreService = FirestoreService.shared
    
    func loadUsers(userId: String, sheetType: UserListSheetType) async {
        isLoading = true
        error = nil
        
        do {
            switch sheetType {
            case .followers:
                users = try await firestoreService.getFollowers(forUserId: userId)
                likes = []
            case .following:
                users = try await firestoreService.getFollowing(forUserId: userId)
                likes = []
            case .likes:
                // Only load likes if it's the current user
                if userId == Auth.auth().currentUser?.uid {
                    likes = try await firestoreService.getUsersWhoLikedContent(forUserId: userId)
                    users = []
                }
            }
        } catch {
            self.error = error.localizedDescription
            print("Error loading \(sheetType.title): \(error)")
        }
        
        isLoading = false
    }
} 