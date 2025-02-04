import Foundation
import Combine
import FirebaseFirestore

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: UserModel?
    @Published var userVideos: [VideoModel] = []
    @Published var isFollowing = false
    
    private var cancellables = Set<AnyCancellable>()
    private var followingStatusListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private var videosListener: ListenerRegistration?
    
    func loadUserProfile(userId: String) async {
        do {
            // Load initial user data
            user = try await FirestoreService.shared.getUser(userId: userId)
            
            // Set up real-time listeners
            setupUserListener(userId: userId)
            setupVideosListener(userId: userId)
            setupFollowingStatusListener(userId: userId)
            
        } catch {
            print("DEBUG: Error loading user profile: \(error.localizedDescription)")
        }
    }
    
    private func setupUserListener(userId: String) {
        userListener = FirestoreService.shared.addUserListener(userId: userId) { [weak self] user in
            self?.user = user
        }
    }
    
    private func setupVideosListener(userId: String) {
        videosListener = FirestoreService.shared.addUserVideosListener(userId: userId) { [weak self] videos in
            self?.userVideos = videos
        }
    }
    
    private func setupFollowingStatusListener(userId: String) {
        followingStatusListener = FirestoreService.shared.addFollowingStatusListener(userId: userId) { [weak self] isFollowing in
            self?.isFollowing = isFollowing
        }
    }
    
    func toggleFollow() async {
        guard let userId = user?.id else { return }
        
        do {
            if isFollowing {
                try await FirestoreService.shared.unfollowUser(userId: userId)
            } else {
                try await FirestoreService.shared.followUser(userId: userId)
            }
        } catch {
            print("DEBUG: Error toggling follow status: \(error.localizedDescription)")
        }
    }
    
    deinit {
        userListener?.remove()
        videosListener?.remove()
        followingStatusListener?.remove()
    }
} 