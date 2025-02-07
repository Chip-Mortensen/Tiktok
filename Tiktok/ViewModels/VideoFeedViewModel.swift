import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [VideoModel] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let firestoreService = FirestoreService.shared
    
    func fetchVideos() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            videos = try await firestoreService.fetchFeedVideos()
            // Check like status for each video
            if let currentUserId = Auth.auth().currentUser?.uid {
                for i in 0..<videos.count {
                    videos[i].isLiked = try await firestoreService.isVideoLikedByUser(videoId: videos[i].id, userId: currentUserId)
                }
            }
        } catch {
            print("DEBUG: Error fetching videos: \(error.localizedDescription)")
            self.error = error
        }
    }
    
    func likeVideo(_ videoId: String) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard let index = videos.firstIndex(where: { $0.id == videoId }) else { return }
        let video = videos[index]
        
        // Prevent duplicate liking
        if video.isLiked { return }
        
        // Optimistic update
        withAnimation {
            videos[index].like()
        }
        
        do {
            try await firestoreService.likeVideo(
                videoId: videoId,
                likerUserId: currentUserId,
                videoOwnerId: video.userId
            )
        } catch {
            // Revert on failure
            withAnimation {
                videos[index].unlike()
            }
            print("DEBUG: Failed to like video: \(error.localizedDescription)")
        }
    }
    
    func unlikeVideo(_ videoId: String) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard let index = videos.firstIndex(where: { $0.id == videoId }) else { return }
        let video = videos[index]
        
        // Prevent unliking when not liked
        if !videos[index].isLiked { return }
        
        // Optimistic update
        withAnimation {
            videos[index].unlike()
        }
        
        do {
            try await firestoreService.unlikeVideo(
                videoId: videoId,
                likerUserId: currentUserId,
                videoOwnerId: video.userId
            )
        } catch {
            // Revert on failure
            withAnimation {
                videos[index].like()
            }
            print("DEBUG: Failed to unlike video: \(error.localizedDescription)")
        }
    }
    
    func isVideoLiked(_ video: VideoModel) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        do {
            return try await firestoreService.isVideoLikedByUser(videoId: video.id, userId: currentUserId)
        } catch {
            print("DEBUG: Failed to check video like status: \(error.localizedDescription)")
            return false
        }
    }
} 