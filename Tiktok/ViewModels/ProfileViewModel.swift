import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var user: UserModel?
    @Published var videoCache: [String: VideoModel] = [:] // Single source of truth
    @Published var isLoading = false
    @Published var error: Error?
    
    private let userService = UserService()
    private let authService = AuthService()
    private let firestoreService = FirestoreService.shared
    private var listeners: [String: ListenerRegistration] = [:]
    
    var posts: [VideoModel] {
        videoCache.values.filter { $0.userId == user?.id }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    var likedPosts: [VideoModel] {
        videoCache.values.filter { $0.isLiked }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    init() {
        Task {
            await fetchUserData()
        }
    }
    
    func fetchUserData() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let userId = Auth.auth().currentUser?.uid else { 
            print("DEBUG: No authenticated user ID found")
            return 
        }
        
        // Start real-time listeners
        startListeners(userId: userId)
    }
    
    private func startListeners(userId: String) {
        // Listen for user changes
        listeners["user"] = firestoreService.addUserListener(userId: userId) { [weak self] user in
            self?.user = user
        }
        
        // Listen for user's videos
        listeners["videos"] = firestoreService.addUserVideosListener(userId: userId) { [weak self] videos in
            guard let self = self else { return }
            
            // Update cache while preserving liked states
            for var video in videos {
                if let existingVideo = self.videoCache[video.id] {
                    video.isLiked = existingVideo.isLiked
                }
                self.videoCache[video.id] = video
            }
        }
        
        // Listen for liked videos
        listeners["likes"] = firestoreService.addUserLikesListener(userId: userId) { [weak self] likedVideoIds in
            guard let self = self else { return }
            
            // Update liked states in cache
            for (videoId, var video) in self.videoCache {
                video.isLiked = likedVideoIds.contains(videoId)
                self.videoCache[videoId] = video
            }
            
            // Fetch any liked videos that aren't in cache
            let missingVideoIds = likedVideoIds.filter { !self.videoCache.keys.contains($0) }
            if !missingVideoIds.isEmpty {
                Task {
                    for videoId in missingVideoIds {
                        if let video = try? await self.firestoreService.fetchVideo(videoId: videoId) {
                            var updatedVideo = video
                            updatedVideo.isLiked = true
                            self.videoCache[videoId] = updatedVideo
                        }
                    }
                }
            }
        }
    }
    
    func likeVideo(_ videoId: String) async {
        guard let userId = user?.id else { return }
        
        // Optimistic update
        if var video = videoCache[videoId] {
            video.like()
            videoCache[videoId] = video
        }
        
        do {
            try await firestoreService.likeVideo(videoId: videoId, userId: userId)
        } catch {
            // Revert on failure
            if var video = videoCache[videoId] {
                video.unlike()
                videoCache[videoId] = video
            }
            print("DEBUG: Failed to like video with error: \(error.localizedDescription)")
        }
    }
    
    func unlikeVideo(_ videoId: String) async {
        guard let userId = user?.id else { return }
        
        // Optimistic update
        if var video = videoCache[videoId] {
            video.unlike()
            videoCache[videoId] = video
        }
        
        do {
            try await firestoreService.unlikeVideo(videoId: videoId, userId: userId)
        } catch {
            // Revert on failure
            if var video = videoCache[videoId] {
                video.like()
                videoCache[videoId] = video
            }
            print("DEBUG: Failed to unlike video with error: \(error.localizedDescription)")
        }
    }
    
    func isVideoLiked(_ video: VideoModel) async -> Bool {
        guard let userId = user?.id else { return false }
        do {
            let isLiked = try await firestoreService.isVideoLikedByUser(videoId: video.id, userId: userId)
            // Update cache
            if var cachedVideo = videoCache[video.id] {
                cachedVideo.isLiked = isLiked
                videoCache[video.id] = cachedVideo
            }
            return isLiked
        } catch {
            print("DEBUG: Failed to check video like status with error: \(error.localizedDescription)")
            return false
        }
    }
    
    func signOut() {
        // Remove all listeners
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        
        // Clear cache
        videoCache.removeAll()
        
        // Sign out
        authService.signOut()
    }
    
    // Method to update a video (after editing)
    func updateVideo(_ video: VideoModel) async {
        do {
            try await firestoreService.updateVideo(video)
            videoCache[video.id] = video
        } catch {
            print("DEBUG: Error updating video: \(error.localizedDescription)")
            // Optionally, set an error state here
            self.error = error
        }
    }

    // Method to delete a video
    func deleteVideo(_ video: VideoModel) async {
        do {
            try await firestoreService.deleteVideo(video: video)
            videoCache.removeValue(forKey: video.id)
        } catch {
            print("DEBUG: Error deleting video: \(error.localizedDescription)")
            // Optionally, set an error state here
            self.error = error
        }
    }
    
    deinit {
        // Clean up listeners
        listeners.values.forEach { $0.remove() }
    }
} 