import Foundation
import FirebaseFirestore

enum FirestoreError: Error {
    case documentNotFound
    case invalidData
    case unknown
}

class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    
    // MARK: - User Methods
    
    func createUser(_ user: UserModel) async throws {
        let userData = user.toDictionary()
        guard let userId = user.id else {
            throw NSError(domain: "FirestoreService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "User ID is required"
            ])
        }
        
        // Start a batch write
        let batch = db.batch()
        
        // Create user document
        let userRef = db.collection("users").document(userId)
        batch.setData(userData, forDocument: userRef)
        
        // Reserve username
        let usernameRef = db.collection("usernames").document(user.username.lowercased())
        batch.setData([
            "userId": userId,
            "username": user.username,
            "createdAt": Timestamp()
        ], forDocument: usernameRef)
        
        // Commit both operations
        try await batch.commit()
    }
    
    func getUser(userId: String) async throws -> UserModel {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard let user = UserModel(document: snapshot) else {
            throw NSError(domain: "FirestoreService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "User not found or invalid data"
            ])
        }
        return user
    }
    
    // MARK: - Username Methods
    
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let lowercaseUsername = username.lowercased()
        let docRef = db.collection("usernames").document(lowercaseUsername)
        let doc = try await docRef.getDocument()
        return !doc.exists
    }
    
    func updateUsername(_ newUsername: String, for user: UserModel) async throws {
        guard let userId = user.id else { return }
        
        // First check if new username is available
        guard try await isUsernameAvailable(newUsername) else {
            throw NSError(domain: "FirestoreService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Username is already taken"
            ])
        }
        
        // Start a batch write
        let batch = db.batch()
        
        // Delete old username document
        let oldUsernameRef = db.collection("usernames").document(user.username.lowercased())
        batch.deleteDocument(oldUsernameRef)
        
        // Create new username document
        let newUsernameRef = db.collection("usernames").document(newUsername.lowercased())
        batch.setData([
            "userId": userId,
            "username": newUsername,
            "createdAt": Timestamp()
        ], forDocument: newUsernameRef)
        
        // Update user document
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "username": newUsername
        ], forDocument: userRef)
        
        // Commit the batch
        try await batch.commit()
    }
    
    // MARK: - Profile Methods
    
    func updateProfile(userId: String, data: [String: Any]) async throws {
        let userRef = db.collection("users").document(userId)
        try await userRef.updateData(data)
    }
    
    // MARK: - Video Methods
    
    func uploadVideo(_ video: VideoModel) async throws {
        print("DEBUG: Starting Firestore video upload for video ID: \(video.id)")
        let videoData: [String: Any] = [
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
        
        // Update the videos collection using the video.id as the document ID
        try await db.collection("videos").document(video.id).setData(videoData)
        print("DEBUG: Video metadata saved to videos collection with ID: \(video.id)")
        
        // Update user's video count
        try await db.collection("users").document(video.userId).updateData([
            "postsCount": FieldValue.increment(Int64(1))
        ])
        print("DEBUG: User's video count updated for user: \(video.userId)")
    }
    
    func fetchVideos(limit: Int = 10) async throws -> [VideoModel] {
        print("Fetching videos from Firestore...")
        let snapshot = try await db.collection("videos")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        print("Found \(snapshot.documents.count) videos")
        
        var videos: [VideoModel] = []
        for document in snapshot.documents {
            let data = document.data()
            let userId = data["userId"] as? String ?? ""
            
            // Fetch username
            let username = try await getUsernameForUserId(userId)
            
            let comments = (data["comments"] as? [[String: Any]])?.compactMap { commentData in
                return VideoModel.Comment(
                    id: commentData["id"] as? String ?? UUID().uuidString,
                    userId: commentData["userId"] as? String ?? "",
                    text: commentData["text"] as? String ?? "",
                    timestamp: (commentData["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                )
            } ?? []
            
            let video = VideoModel(
                id: document.documentID,
                userId: userId,
                username: username,
                videoUrl: data["videoUrl"] as? String ?? "",
                caption: data["caption"] as? String ?? "",
                likes: data["likes"] as? Int ?? 0,
                comments: comments,
                timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                thumbnailUrl: data["thumbnailUrl"] as? String
            )
            videos.append(video)
        }
        
        return videos
    }
    
    func getUsernameForUserId(_ userId: String) async throws -> String? {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        return userDoc.data()?["username"] as? String
    }
    
    func fetchUserVideos(userId: String) async throws -> [VideoModel] {
        print("DEBUG: Fetching videos for user: \(userId)")
        
        // First get the username
        let username = try await getUsernameForUserId(userId)
        
        let snapshot = try await db.collection("videos")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        print("DEBUG: Found \(snapshot.documents.count) videos for user \(userId)")
        
        let videos = snapshot.documents.compactMap { document in
            let data = document.data()
            print("DEBUG: Processing video document: \(document.documentID)")
            print("DEBUG: Video data: \(data)")
            
            let comments = (data["comments"] as? [[String: Any]])?.compactMap { commentData in
                return VideoModel.Comment(
                    id: commentData["id"] as? String ?? UUID().uuidString,
                    userId: commentData["userId"] as? String ?? "",
                    text: commentData["text"] as? String ?? "",
                    timestamp: (commentData["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                )
            } ?? []
            
            return VideoModel(
                id: document.documentID,
                userId: data["userId"] as? String ?? "",
                username: username,
                videoUrl: data["videoUrl"] as? String ?? "",
                caption: data["caption"] as? String ?? "",
                likes: data["likes"] as? Int ?? 0,
                comments: comments,
                timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                thumbnailUrl: data["thumbnailUrl"] as? String
            )
        }
        
        print("DEBUG: Returning \(videos.count) processed videos")
        return videos
    }
    
    func fetchUserLikedVideos(userId: String) async throws -> [VideoModel] {
        print("Fetching liked videos for user: \(userId)")
        // First get the liked video IDs
        let likedSnapshot = try await db.collection("userLikes")
            .document(userId)
            .collection("likedVideos")
            .getDocuments()
        
        let videoIds = likedSnapshot.documents.map { $0.documentID }
        guard !videoIds.isEmpty else { return [] }
        
        // Then fetch the actual videos
        let chunks = stride(from: 0, to: videoIds.count, by: 10).map {
            Array(videoIds[$0..<min($0 + 10, videoIds.count)])
        }
        
        var videos: [VideoModel] = []
        for chunk in chunks {
            let chunkSnapshot = try await db.collection("videos")
                .whereField("id", in: chunk)
                .getDocuments()
            
            for document in chunkSnapshot.documents {
                let data = document.data()
                let videoUserId = data["userId"] as? String ?? ""
                
                // Fetch username for video owner
                let username = try await getUsernameForUserId(videoUserId)
                
                let comments = (data["comments"] as? [[String: Any]])?.compactMap { commentData in
                    return VideoModel.Comment(
                        id: commentData["id"] as? String ?? UUID().uuidString,
                        userId: commentData["userId"] as? String ?? "",
                        text: commentData["text"] as? String ?? "",
                        timestamp: (commentData["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    )
                } ?? []
                
                let video = VideoModel(
                    id: document.documentID,
                    userId: videoUserId,
                    username: username,
                    videoUrl: data["videoUrl"] as? String ?? "",
                    caption: data["caption"] as? String ?? "",
                    likes: data["likes"] as? Int ?? 0,
                    comments: comments,
                    timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                    thumbnailUrl: data["thumbnailUrl"] as? String
                )
                videos.append(video)
            }
        }
        
        return videos.sorted { $0.timestamp > $1.timestamp }
    }
    
    func likeVideo(videoId: String, userId: String) async throws {
        let batch = db.batch()
        
        // Add to user's liked videos
        let likeRef = db.collection("userLikes")
            .document(userId)
            .collection("likedVideos")
            .document(videoId)
        
        batch.setData(["timestamp": FieldValue.serverTimestamp()], forDocument: likeRef)
        
        // Increment video likes count
        let videoRef = db.collection("videos").document(videoId)
        batch.updateData(["likes": FieldValue.increment(Int64(1))], forDocument: videoRef)
        
        try await batch.commit()
    }
    
    func unlikeVideo(videoId: String, userId: String) async throws {
        let batch = db.batch()
        
        // Remove from user's liked videos
        let likeRef = db.collection("userLikes")
            .document(userId)
            .collection("likedVideos")
            .document(videoId)
        
        batch.deleteDocument(likeRef)
        
        // Decrement video likes count
        let videoRef = db.collection("videos").document(videoId)
        batch.updateData(["likes": FieldValue.increment(Int64(-1))], forDocument: videoRef)
        
        try await batch.commit()
    }
    
    func isVideoLikedByUser(videoId: String, userId: String) async throws -> Bool {
        let docSnapshot = try await db.collection("userLikes")
            .document(userId)
            .collection("likedVideos")
            .document(videoId)
            .getDocument()
        
        return docSnapshot.exists
    }
    
    func fetchVideo(videoId: String) async throws -> VideoModel {
        let videoDoc = try await db.collection("videos").document(videoId).getDocument()
        
        guard let data = videoDoc.data() else {
            throw FirestoreError.documentNotFound
        }
        
        // Get the user data for the video
        let userId = data["userId"] as? String ?? ""
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let userData = userDoc.data()
        let username = userData?["username"] as? String
        
        // Create the video model
        return VideoModel(
            id: videoDoc.documentID,
            userId: userId,
            username: username,
            videoUrl: data["videoUrl"] as? String ?? "",
            caption: data["caption"] as? String ?? "",
            likes: data["likes"] as? Int ?? 0,
            comments: data["comments"] as? [VideoModel.Comment] ?? [],
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
            thumbnailUrl: data["thumbnailUrl"] as? String
        )
    }
    
    // MARK: - Snapshot Listeners
    
    func addUserListener(userId: String, onChange: @escaping (UserModel?) -> Void) -> ListenerRegistration {
        return db.collection("users").document(userId)
            .addSnapshotListener { snapshot, error in
                guard let document = snapshot else {
                    print("DEBUG: Error fetching user: \(error?.localizedDescription ?? "")")
                    return
                }
                
                guard let user = UserModel(document: document) else {
                    print("DEBUG: Error decoding user data")
                    return
                }
                
                onChange(user)
            }
    }
    
    func addUserVideosListener(userId: String, onChange: @escaping ([VideoModel]) -> Void) -> ListenerRegistration {
        return db.collection("videos")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let documents = snapshot?.documents else {
                    print("DEBUG: Error fetching videos: \(error?.localizedDescription ?? "")")
                    return
                }
                
                Task {
                    // Create local array to avoid concurrent access
                    let processedVideos = await withTaskGroup(of: VideoModel?.self) { group in
                        for document in documents {
                            group.addTask {
                                let data = document.data()
                                let userId = data["userId"] as? String ?? ""
                                
                                // Fetch username for each video
                                let username = try? await self.getUsernameForUserId(userId)
                                
                                let comments = (data["comments"] as? [[String: Any]])?.compactMap { commentData in
                                    return VideoModel.Comment(
                                        id: commentData["id"] as? String ?? UUID().uuidString,
                                        userId: commentData["userId"] as? String ?? "",
                                        text: commentData["text"] as? String ?? "",
                                        timestamp: (commentData["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                                    )
                                } ?? []
                                
                                return VideoModel(
                                    id: document.documentID,
                                    userId: userId,
                                    username: username,
                                    videoUrl: data["videoUrl"] as? String ?? "",
                                    caption: data["caption"] as? String ?? "",
                                    likes: data["likes"] as? Int ?? 0,
                                    comments: comments,
                                    timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                                    thumbnailUrl: data["thumbnailUrl"] as? String
                                )
                            }
                        }
                        
                        var videos: [VideoModel] = []
                        for await video in group {
                            if let video = video {
                                videos.append(video)
                            }
                        }
                        return videos
                    }
                    
                    await MainActor.run {
                        onChange(processedVideos)
                    }
                }
            }
    }
    
    func addUserLikesListener(userId: String, onChange: @escaping ([String]) -> Void) -> ListenerRegistration {
        return db.collection("userLikes")
            .document(userId)
            .collection("likedVideos")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("DEBUG: Error fetching liked videos: \(error?.localizedDescription ?? "")")
                    return
                }
                
                let videoIds = documents.map { $0.documentID }
                onChange(videoIds)
            }
    }
} 