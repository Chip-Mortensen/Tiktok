import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class BookmarkService: ObservableObject {
    static let shared = BookmarkService()
    private init() { }
    
    @Published var bookmarkedVideoIds: Set<String> = []
    private let firestoreService = FirestoreService.shared
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        listener = db.collection("userBookmarks")
            .document(userId)
            .collection("bookmarkedVideos")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("DEBUG: Error fetching bookmarks: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                self?.bookmarkedVideoIds = Set(documents.map { $0.documentID })
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        bookmarkedVideoIds = []
    }
    
    func toggleBookmark(for video: inout VideoModel) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            if bookmarkedVideoIds.contains(video.id) {
                // Unbookmark video
                try await unbookmarkVideo(videoId: video.id, userId: userId)
                video.unbookmark()
            } else {
                // Bookmark video
                try await bookmarkVideo(videoId: video.id, userId: userId)
                video.bookmark()
            }
        } catch {
            print("DEBUG: Error toggling bookmark: \(error.localizedDescription)")
        }
    }
    
    private func bookmarkVideo(videoId: String, userId: String) async throws {
        let data: [String: Any] = [
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        let docRef = db.collection("userBookmarks")
            .document(userId)
            .collection("bookmarkedVideos")
            .document(videoId)
            
        try await docRef.setData(data)
    }
    
    private func unbookmarkVideo(videoId: String, userId: String) async throws {
        let docRef = db.collection("userBookmarks")
            .document(userId)
            .collection("bookmarkedVideos")
            .document(videoId)
            
        try await docRef.delete()
    }
    
    func fetchBookmarkedVideos() async throws -> [VideoModel] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        
        // Get all bookmarked video IDs
        let bookmarksSnapshot = try await db.collection("userBookmarks")
            .document(userId)
            .collection("bookmarkedVideos")
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        let videoIds = bookmarksSnapshot.documents.map { $0.documentID }
        
        // Fetch each video document
        var videos: [VideoModel] = []
        for videoId in videoIds {
            if let video = try? await fetchVideo(videoId: videoId) {
                var bookmarkedVideo = video
                bookmarkedVideo.isBookmarked = true
                videos.append(bookmarkedVideo)
            }
        }
        
        return videos
    }
    
    private func fetchVideo(videoId: String) async throws -> VideoModel? {
        let doc = try await db.collection("videos").document(videoId).getDocument()
        guard let data = doc.data() else { return nil }
        
        let userId = data["userId"] as? String ?? ""
        let username = try await firestoreService.getUsernameForUserId(userId)
        
        let comments = (data["comments"] as? [[String: Any]])?.compactMap { commentData in
            return VideoModel.Comment(
                id: commentData["id"] as? String ?? UUID().uuidString,
                userId: commentData["userId"] as? String ?? "",
                text: commentData["text"] as? String ?? "",
                timestamp: (commentData["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            )
        } ?? []
        
        return VideoModel(
            id: doc.documentID,
            userId: userId,
            username: username,
            videoUrl: data["videoUrl"] as? String ?? "",
            caption: data["caption"] as? String ?? "",
            likes: data["likes"] as? Int ?? 0,
            comments: comments,
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
            thumbnailUrl: data["thumbnailUrl"] as? String,
            m3u8Url: data["m3u8Url"] as? String,
            isBookmarked: true,
            commentsCount: data["commentsCount"] as? Int ?? 0
        )
    }
} 