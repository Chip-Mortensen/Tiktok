import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class VideoService: ObservableObject {
    static let shared = VideoService()
    private init() {}  // Make constructor private

    @Published var videos: [String: VideoModel] = [:]  // keyed by video.id
    private let firestoreService = FirestoreService.shared
    private var listeners: [String: ListenerRegistration] = [:]
    
    // Track optimistic updates separately from the main state
    private var optimisticUpdates: [String: (isLiked: Bool, likes: Int)] = [:]
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    
    // Public method to check if a video is liked
    func checkIfVideoIsLiked(videoId: String) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        do {
            return try await firestoreService.isVideoLikedByUser(
                videoId: videoId,
                userId: currentUserId
            )
        } catch {
            print("DEBUG: Failed to check video like status: \(error.localizedDescription)")
            return false
        }
    }
    
    func setupVideoListener(videoId: String) {
        // Remove existing listener if any
        listeners[videoId]?.remove()
        
        // Cancel any pending tasks for this video
        pendingTasks[videoId]?.cancel()
        pendingTasks.removeValue(forKey: videoId)
        
        // Setup new listener
        listeners[videoId] = firestoreService.addVideoListener(videoId: videoId) { [weak self] updatedVideo in
            guard let self = self else { return }
            Task {
                if let updatedVideo = updatedVideo {
                    // Create a mutable copy of the updated video
                    var newVideo = updatedVideo
                    
                    // If we have an optimistic update pending, use those values
                    if let optimisticUpdate = self.optimisticUpdates[videoId] {
                        newVideo.isLiked = optimisticUpdate.isLiked
                        newVideo.likes = optimisticUpdate.likes
                    } else {
                        // No optimistic update, fetch real state
                        let isLiked = try? await self.firestoreService.isVideoLikedByUser(
                            videoId: videoId,
                            userId: Auth.auth().currentUser?.uid ?? ""
                        )
                        newVideo.isLiked = isLiked ?? false
                    }
                    
                    // If we already have this video in our state, preserve any local state
                    if let existingVideo = self.videos[videoId] {
                        newVideo.isBookmarked = existingVideo.isBookmarked
                    }
                    
                    // Update the video in our state with animation
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            self.videos[videoId] = newVideo
                        }
                    }
                }
            }
        }
    }
    
    func removeListener(videoId: String) {
        listeners[videoId]?.remove()
        listeners.removeValue(forKey: videoId)
        optimisticUpdates.removeValue(forKey: videoId)
        pendingTasks[videoId]?.cancel()
        pendingTasks.removeValue(forKey: videoId)
    }
    
    func toggleLike(for videoId: String) async {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let video = videos[videoId] else { return }
        
        // Cancel any existing pending task for this video
        pendingTasks[videoId]?.cancel()
        
        // If we have an optimistic update that's different from the current state,
        // it means the previous action hasn't completed yet, so skip this tap
        if let existingUpdate = optimisticUpdates[videoId],
           existingUpdate.isLiked != video.isLiked {
            return
        }
        
        // Calculate new state
        let newIsLiked = !video.isLiked
        let newLikes = video.likes + (newIsLiked ? 1 : -1)
        
        // Store optimistic update
        optimisticUpdates[videoId] = (isLiked: newIsLiked, likes: newLikes)
        
        // Update UI immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            var updatedVideo = video
            updatedVideo.isLiked = newIsLiked
            updatedVideo.likes = newLikes
            videos[videoId] = updatedVideo
        }
        
        // Create a new task for this toggle operation
        let task = Task {
            do {
                // Make backend call
                if newIsLiked {
                    try await firestoreService.likeVideo(
                        videoId: videoId,
                        likerUserId: currentUserId,
                        videoOwnerId: video.userId
                    )
                } else {
                    try await firestoreService.unlikeVideo(
                        videoId: videoId,
                        likerUserId: currentUserId,
                        videoOwnerId: video.userId
                    )
                }
                
                if !Task.isCancelled {
                    // Wait before clearing optimistic update to ensure server sync
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    optimisticUpdates.removeValue(forKey: videoId)
                }
            } catch {
                print("DEBUG: Failed to toggle like with error: \(error.localizedDescription)")
                
                if !Task.isCancelled {
                    // On failure, clear optimistic update and revert to server state
                    optimisticUpdates.removeValue(forKey: videoId)
                    
                    // Fetch latest state from server
                    if let updatedVideo = try? await firestoreService.fetchVideo(videoId: videoId) {
                        let isLiked = try? await firestoreService.isVideoLikedByUser(
                            videoId: videoId,
                            userId: currentUserId
                        )
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            var newVideo = updatedVideo
                            newVideo.isLiked = isLiked ?? false
                            videos[videoId] = newVideo
                        }
                    }
                }
            }
        }
        
        // Store the task
        pendingTasks[videoId] = task
    }
    
    deinit {
        // Clean up all listeners
        listeners.values.forEach { $0.remove() }
        // Cancel all pending tasks
        pendingTasks.values.forEach { $0.cancel() }
    }
} 