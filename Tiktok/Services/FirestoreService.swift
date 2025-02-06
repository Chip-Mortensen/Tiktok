import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

enum FirestoreError: Error {
    case documentNotFound
    case invalidData
    case unknown
    case selfFollow
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
            "thumbnailUrl": video.thumbnailUrl as Any,
            "m3u8Url": video.m3u8Url as Any
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
    
    func updateVideo(_ video: VideoModel) async throws {
        let videoRef = db.collection("videos").document(video.id)
        // For now, we update only the caption. You can extend this to add other fields.
        try await videoRef.updateData([
            "caption": video.caption
        ])
    }
    
    // Method to delete a video
    func deleteVideo(video: VideoModel) async throws {
        // Delete from Firestore
        let videoRef = db.collection("videos").document(video.id)
        try await videoRef.delete()

        // Delete video and thumbnail from Storage
        let storage = Storage.storage().reference()
        
        // Construct storage paths
        let videoPath = "videos/\(video.userId)/\(video.id).mp4"
        let thumbnailPath = "thumbnails/\(video.userId)/\(video.id).jpg"
        let hlsBasePath = "hls/\(video.userId)/\(video.id)"
        
        // Delete video file
        let videoStorageRef = storage.child(videoPath)
        try await videoStorageRef.delete()
        
        // Delete thumbnail file if it exists
        if video.thumbnailUrl != nil {
            let thumbnailStorageRef = storage.child(thumbnailPath)
            try await thumbnailStorageRef.delete()
        }

        // Delete HLS files if they exist
        if video.m3u8Url != nil {
            // List all files in the HLS directory
            let hlsRef = storage.child(hlsBasePath)
            let hlsFiles = try await hlsRef.listAll()
            
            // Delete each file in the HLS directory
            for item in hlsFiles.items {
                try await item.delete()
            }
        }

        // Also decrement the posts count for the user
        let userRef = db.collection("users").document(video.userId)
        try await userRef.updateData([
            "postsCount": FieldValue.increment(Int64(-1))
        ])
    }
    
    func fetchVideos(limit: Int = 10) async throws -> [VideoModel] {
        print("Fetching videos from Firestore...")
        let snapshot = try await db.collection("videos")
            .order(by: "timestamp", descending: false)
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
                thumbnailUrl: data["thumbnailUrl"] as? String,
                m3u8Url: data["m3u8Url"] as? String,
                commentsCount: data["commentsCount"] as? Int ?? 0
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
            .order(by: "timestamp", descending: false)
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
                thumbnailUrl: data["thumbnailUrl"] as? String,
                m3u8Url: data["m3u8Url"] as? String,
                commentsCount: data["commentsCount"] as? Int ?? 0
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
                    thumbnailUrl: data["thumbnailUrl"] as? String,
                    m3u8Url: data["m3u8Url"] as? String,
                    commentsCount: data["commentsCount"] as? Int ?? 0
                )
                videos.append(video)
            }
        }
        
        return videos.sorted { $0.timestamp > $1.timestamp }
    }
    
    func likeVideo(videoId: String, likerUserId: String, videoOwnerId: String) async throws {
        let batch = db.batch()
        
        // Store the like document in the liker's subcollection
        let likeRef = db.collection("userLikes")
            .document(likerUserId)
            .collection("likedVideos")
            .document(videoId)
        
        // Check if the like already exists
        let likeDoc = try await likeRef.getDocument()
        if likeDoc.exists {
            // Like already exists, don't proceed
            return
        }
        
        batch.setData([
            "videoId": videoId,
            "userId": likerUserId,
            "timestamp": FieldValue.serverTimestamp()
        ], forDocument: likeRef)
        
        // Increment video likes count
        let videoRef = db.collection("videos").document(videoId)
        batch.updateData(["likes": FieldValue.increment(Int64(1))], forDocument: videoRef)
        
        // Increment the video owner's likesCount field in their user document
        let ownerRef = db.collection("users").document(videoOwnerId)
        batch.updateData(["likesCount": FieldValue.increment(Int64(1))], forDocument: ownerRef)
        
        try await batch.commit()
    }
    
    func unlikeVideo(videoId: String, likerUserId: String, videoOwnerId: String) async throws {
        let batch = db.batch()
        
        // Remove the like document
        let likeRef = db.collection("userLikes")
            .document(likerUserId)
            .collection("likedVideos")
            .document(videoId)
        
        // Check if the like exists before trying to remove it
        let likeDoc = try await likeRef.getDocument()
        if !likeDoc.exists {
            // Like doesn't exist, don't proceed
            return
        }
        
        batch.deleteDocument(likeRef)
        
        // Decrement video likes count
        let videoRef = db.collection("videos").document(videoId)
        batch.updateData(["likes": FieldValue.increment(Int64(-1))], forDocument: videoRef)
        
        // Decrement the video owner's likesCount field
        let ownerRef = db.collection("users").document(videoOwnerId)
        batch.updateData(["likesCount": FieldValue.increment(Int64(-1))], forDocument: ownerRef)
        
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
            thumbnailUrl: data["thumbnailUrl"] as? String,
            m3u8Url: data["m3u8Url"] as? String,
            commentsCount: data["commentsCount"] as? Int ?? 0
        )
    }
    
    // MARK: - Comment Methods
    
    func addComment(videoId: String, text: String) async throws {
        print("DEBUG: Starting to add comment for video: \(videoId)")
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let batch = db.batch()
        
        // Create the comment document
        let commentRef = db.collection("comments").document()
        let commentData: [String: Any] = [
            "videoId": videoId,
            "userId": currentUserId,
            "text": text,
            "timestamp": FieldValue.serverTimestamp()
        ]
        print("DEBUG: Creating comment document with ID: \(commentRef.documentID)")
        batch.setData(commentData, forDocument: commentRef)
        
        // Update video's comment count
        let videoRef = db.collection("videos").document(videoId)
        print("DEBUG: Updating video document: \(videoId) to increment comment count")
        batch.updateData([
            "commentsCount": FieldValue.increment(Int64(1))
        ], forDocument: videoRef)
        
        // Commit both operations
        print("DEBUG: Committing batch write...")
        try await batch.commit()
        print("DEBUG: Successfully added comment and updated video count")
    }
    
    func fetchComments(forVideoId videoId: String) async throws -> [CommentModel] {
        let snapshot = try await db.collection("comments")
            .whereField("videoId", isEqualTo: videoId)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        var comments = snapshot.documents.compactMap { CommentModel(document: $0) }
        
        // Fetch user data for each comment
        for i in 0..<comments.count {
            if let user = try? await getUser(userId: comments[i].userId) {
                comments[i].username = user.username
                comments[i].profileImageUrl = user.profileImageUrl
            }
        }
        
        return comments
    }
    
    func addCommentsListener(forVideoId videoId: String, onChange: @escaping ([CommentModel]) -> Void) -> ListenerRegistration {
        return db.collection("comments")
            .whereField("videoId", isEqualTo: videoId)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let documents = snapshot?.documents else {
                    print("DEBUG: Error fetching comments: \(error?.localizedDescription ?? "")")
                    return
                }
                
                Task {
                    // Create immutable comments array from documents
                    let initialComments = documents.compactMap { CommentModel(document: $0) }
                    
                    // Create new array with user data
                    let updatedComments = await withTaskGroup(of: (Int, CommentModel).self) { group in
                        for (index, comment) in initialComments.enumerated() {
                            group.addTask {
                                var updatedComment = comment
                                if let user = try? await self.getUser(userId: comment.userId) {
                                    updatedComment.username = user.username
                                    updatedComment.profileImageUrl = user.profileImageUrl
                                }
                                return (index, updatedComment)
                            }
                        }
                        
                        // Collect results maintaining order
                        var orderedComments: [CommentModel] = []
                        var indexedComments: [(Int, CommentModel)] = []
                        for await result in group {
                            indexedComments.append(result)
                        }
                        
                        // Sort by original index and extract comments
                        orderedComments = indexedComments.sorted { $0.0 < $1.0 }.map { $0.1 }
                        return orderedComments
                    }
                    
                    await MainActor.run {
                        onChange(updatedComments)
                    }
                }
            }
    }
    
    // MARK: - Snapshot Listeners
    
    func addUserListener(userId: String, onChange: @escaping (UserModel?) -> Void) -> ListenerRegistration {
        return db.collection("users").document(userId)
            .addSnapshotListener(includeMetadataChanges: false) { snapshot, error in
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
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
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
                                    thumbnailUrl: data["thumbnailUrl"] as? String,
                                    m3u8Url: data["m3u8Url"] as? String,
                                    commentsCount: data["commentsCount"] as? Int ?? 0
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
    
    func addVideoListener(videoId: String, onChange: @escaping (VideoModel?) -> Void) -> ListenerRegistration {
        return db.collection("videos").document(videoId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let document = snapshot else {
                    print("DEBUG: Error fetching video: \(error?.localizedDescription ?? "")")
                    return
                }
                
                guard let data = document.data() else {
                    onChange(nil)
                    return
                }
                
                Task {
                    // Get the user data for the video
                    let userId = data["userId"] as? String ?? ""
                    let username = try? await self.getUsernameForUserId(userId)
                    
                    let video = VideoModel(
                        id: document.documentID,
                        userId: userId,
                        username: username,
                        videoUrl: data["videoUrl"] as? String ?? "",
                        caption: data["caption"] as? String ?? "",
                        likes: data["likes"] as? Int ?? 0,
                        comments: data["comments"] as? [VideoModel.Comment] ?? [],
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        thumbnailUrl: data["thumbnailUrl"] as? String,
                        m3u8Url: data["m3u8Url"] as? String,
                        commentsCount: data["commentsCount"] as? Int ?? 0
                    )
                    
                    await MainActor.run {
                        onChange(video)
                    }
                }
            }
    }
    
    // MARK: - Following Methods
    
    func followUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard currentUserId != userId else { throw FirestoreError.selfFollow }
        
        let batch = db.batch()
        
        // Add following relationship
        let followingRef = db.collection("users")
            .document(currentUserId)
            .collection("userFollowing")
            .document(userId)
        
        batch.setData([
            "timestamp": FieldValue.serverTimestamp()
        ], forDocument: followingRef)
        
        // Add to followers collection
        let followerRef = db.collection("users")
            .document(userId)
            .collection("userFollowers")
            .document(currentUserId)
        
        batch.setData([
            "timestamp": FieldValue.serverTimestamp()
        ], forDocument: followerRef)
        
        // Update follower count for followed user
        let followedUserRef = db.collection("users").document(userId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(1))
        ], forDocument: followedUserRef)
        
        // Update following count for current user
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(1))
        ], forDocument: currentUserRef)
        
        try await batch.commit()
    }
    
    func unfollowUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard currentUserId != userId else { throw FirestoreError.selfFollow }
        
        let batch = db.batch()
        
        // Remove following relationship
        let followingRef = db.collection("users")
            .document(currentUserId)
            .collection("userFollowing")
            .document(userId)
        
        batch.deleteDocument(followingRef)
        
        // Remove from followers collection
        let followerRef = db.collection("users")
            .document(userId)
            .collection("userFollowers")
            .document(currentUserId)
        
        batch.deleteDocument(followerRef)
        
        // Update follower count for unfollowed user
        let followedUserRef = db.collection("users").document(userId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(-1))
        ], forDocument: followedUserRef)
        
        // Update following count for current user
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(-1))
        ], forDocument: currentUserRef)
        
        try await batch.commit()
    }
    
    func isFollowingUser(userId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        
        let followingRef = db.collection("users")
            .document(currentUserId)
            .collection("userFollowing")
            .document(userId)
        
        let snapshot = try await followingRef.getDocument()
        return snapshot.exists
    }
    
    func addFollowingStatusListener(userId: String, onChange: @escaping (Bool) -> Void) -> ListenerRegistration {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            onChange(false)
            // Return a no-op listener since we can't create a real one
            return db.collection("users").document("dummy").addSnapshotListener { _, _ in }
        }
        
        return db.collection("users")
            .document(currentUserId)
            .collection("userFollowing")
            .document(userId)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot else {
                    print("DEBUG: Error fetching following status: \(error?.localizedDescription ?? "")")
                    onChange(false)
                    return
                }
                onChange(snapshot.exists)
            }
    }
    
    func getFollowers(forUserId userId: String) async throws -> [UserModel] {
        let followersSnapshot = try await db.collection("users")
            .document(userId)
            .collection("userFollowers")
            .getDocuments()
        
        var followers: [UserModel] = []
        for document in followersSnapshot.documents {
            if let user = try? await getUser(userId: document.documentID) {
                followers.append(user)
            }
        }
        return followers
    }
    
    func getFollowing(forUserId userId: String) async throws -> [UserModel] {
        let followingSnapshot = try await db.collection("users")
            .document(userId)
            .collection("userFollowing")
            .getDocuments()
        
        var following: [UserModel] = []
        for document in followingSnapshot.documents {
            if let user = try? await getUser(userId: document.documentID) {
                following.append(user)
            }
        }
        return following
    }
    
    // MARK: - User Like Methods
    
    func getUsersWhoLikedContent(forUserId userId: String) async throws -> [LikeModel] {
        print("DEBUG: Fetching likes for content of user: \(userId)")
        
        // Get all videos by the user
        let videosQuery = db.collection("videos")
            .whereField("userId", isEqualTo: userId)
        
        let videosSnapshot = try await videosQuery.getDocuments()
        print("DEBUG: Found \(videosSnapshot.documents.count) videos")
        
        var likes: [LikeModel] = []
        
        // For each video, query the userLikes collection for users who liked it
        for videoDoc in videosSnapshot.documents {
            let videoId = videoDoc.documentID
            print("DEBUG: Processing video: \(videoId)")
            
            // Query all likedVideos collections for documents with this videoId
            let likesQuery = db.collectionGroup("likedVideos")
                .whereField("videoId", isEqualTo: videoId)
            
            let likesSnapshot = try await likesQuery.getDocuments()
            print("DEBUG: Found \(likesSnapshot.documents.count) likes for video \(videoId)")
            
            // Process each like document
            for likeDoc in likesSnapshot.documents {
                if var like = LikeModel(document: likeDoc) {
                    // Skip if this is a self-like
                    if like.userId == userId {
                        continue
                    }
                    
                    // Fetch user details for the liker
                    if let user = try? await getUser(userId: like.userId) {
                        like.username = user.username
                        like.profileImageUrl = user.profileImageUrl
                        likes.append(like)
                        print("DEBUG: Added like from user: \(user.username)")
                    }
                }
            }
        }
        
        // Sort likes by timestamp, most recent first
        let sortedLikes = likes.sorted { $0.timestamp > $1.timestamp }
        print("DEBUG: Returning \(sortedLikes.count) sorted likes")
        return sortedLikes
    }
} 