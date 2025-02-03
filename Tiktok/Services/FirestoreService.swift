import Foundation
import FirebaseFirestore

class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    
    // MARK: - User Methods
    
    func createUser(_ user: UserModel) async throws {
        let userData: [String: Any] = [
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "profileImageUrl": user.profileImageUrl as Any,
            "bio": user.bio as Any,
            "followers": user.followers,
            "following": user.following,
            "videosCount": user.videosCount
        ]
        
        try await db.collection("users").document(user.id).setData(userData)
    }
    
    func getUser(userId: String) async throws -> UserModel {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard let data = snapshot.data() else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        return UserModel(
            id: data["id"] as? String ?? "",
            username: data["username"] as? String ?? "",
            email: data["email"] as? String ?? "",
            profileImageUrl: data["profileImageUrl"] as? String,
            bio: data["bio"] as? String,
            followers: data["followers"] as? Int ?? 0,
            following: data["following"] as? Int ?? 0,
            videosCount: data["videosCount"] as? Int ?? 0
        )
    }
    
    // MARK: - Video Methods
    
    func uploadVideo(_ video: VideoModel) async throws {
        print("Starting Firestore video upload...")
        let videoData: [String: Any] = [
            "id": video.id,
            "userId": video.userId,
            "videoUrl": video.videoUrl,
            "caption": video.caption,
            "likes": video.likes,
            "comments": video.comments.map { comment in
                return [
                    "id": comment.id,
                    "userId": comment.userId,
                    "text": comment.text,
                    "timestamp": comment.timestamp
                ]
            },
            "timestamp": FieldValue.serverTimestamp(),
            "thumbnailUrl": video.thumbnailUrl as Any
        ]
        
        // Update the videos collection
        try await db.collection("videos").document(video.id).setData(videoData)
        print("Video metadata saved to videos collection")
        
        // Update user's video count
        try await db.collection("users").document(video.userId).updateData([
            "videosCount": FieldValue.increment(Int64(1))
        ])
        print("User's video count updated")
    }
    
    func fetchVideos(limit: Int = 10) async throws -> [VideoModel] {
        print("Fetching videos from Firestore...")
        let snapshot = try await db.collection("videos")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        print("Found \(snapshot.documents.count) videos")
        return snapshot.documents.compactMap { document in
            let data = document.data()
            
            let comments = (data["comments"] as? [[String: Any]])?.compactMap { commentData in
                return VideoModel.Comment(
                    id: commentData["id"] as? String ?? UUID().uuidString,
                    userId: commentData["userId"] as? String ?? "",
                    text: commentData["text"] as? String ?? "",
                    timestamp: (commentData["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                )
            } ?? []
            
            return VideoModel(
                id: data["id"] as? String ?? "",
                userId: data["userId"] as? String ?? "",
                videoUrl: data["videoUrl"] as? String ?? "",
                caption: data["caption"] as? String ?? "",
                likes: data["likes"] as? Int ?? 0,
                comments: comments,
                timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                thumbnailUrl: data["thumbnailUrl"] as? String
            )
        }
    }
    
    func updateVideoLikes(videoId: String, likes: Int) async throws {
        try await db.collection("videos").document(videoId).updateData([
            "likes": likes
        ])
    }
    
    func addComment(to videoId: String, comment: VideoModel.Comment) async throws {
        let commentData: [String: Any] = [
            "id": comment.id,
            "userId": comment.userId,
            "text": comment.text,
            "timestamp": comment.timestamp
        ]
        
        try await db.collection("videos").document(videoId).updateData([
            "comments": FieldValue.arrayUnion([commentData])
        ])
    }
} 