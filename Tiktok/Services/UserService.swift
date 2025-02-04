import Foundation
import FirebaseAuth
import FirebaseFirestore

class UserService: ObservableObject {
    @Published var currentUser: UserModel?
    private let db = Firestore.firestore()
    
    // MARK: - Username Management
    
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let lowercaseUsername = username.lowercased()
        let docRef = db.collection("usernames").document(lowercaseUsername)
        let doc = try await docRef.getDocument()
        return !doc.exists
    }
    
    private func ensureUsernameReservation(username: String, userId: String) async throws {
        let lowercaseUsername = username.lowercased()
        let docRef = db.collection("usernames").document(lowercaseUsername)
        let doc = try await docRef.getDocument()
        
        if !doc.exists {
            // Username reservation doesn't exist, create it
            try await docRef.setData([
                "userId": userId,
                "username": username,
                "createdAt": Timestamp()
            ])
        } else if let existingUserId = doc.data()?["userId"] as? String, existingUserId != userId {
            // Username is taken by someone else
            throw NSError(domain: "UserService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Username is already taken"
            ])
        }
        // If the document exists and belongs to this user, we're good
    }
    
    func updateUsername(_ newUsername: String, for user: UserModel) async throws {
        guard let userId = user.id else { return }
        
        // First check if new username is available
        let lowercaseNewUsername = newUsername.lowercased()
        let newUsernameDoc = try await db.collection("usernames").document(lowercaseNewUsername).getDocument()
        
        if newUsernameDoc.exists {
            guard let existingUserId = newUsernameDoc.data()?["userId"] as? String,
                  existingUserId == userId else {
                throw NSError(domain: "UserService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Username is already taken"
                ])
            }
            // If we get here, the user already owns this username
            return
        }
        
        // Start a batch write
        let batch = db.batch()
        
        // Ensure old username reservation exists before trying to delete it
        try await ensureUsernameReservation(username: user.username, userId: userId)
        
            // Delete old username document
            let oldUsernameRef = db.collection("usernames").document(user.username.lowercased())
            batch.deleteDocument(oldUsernameRef)
        
        // Create new username document
        let newUsernameRef = db.collection("usernames").document(lowercaseNewUsername)
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
    
    // MARK: - Profile Management
    
    func updateProfile(userId: String, data: [String: Any]) async throws {
        let userRef = db.collection("users").document(userId)
        try await userRef.updateData(data)
    }
    
    func getUser(withId userId: String) async throws -> UserModel {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard let user = UserModel(document: snapshot) else {
            throw NSError(domain: "UserService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode user data"
            ])
        }
        return user
    }
    
    func getUserByUsername(_ username: String) async throws -> UserModel {
        // First get the userId from usernames collection
        let lowercaseUsername = username.lowercased()
        let usernameDoc = try await db.collection("usernames")
            .document(lowercaseUsername)
            .getDocument()
        
        guard let userId = usernameDoc.data()?["userId"] as? String else {
            throw NSError(domain: "UserService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Username not found"
            ])
        }
        
        // Then get the user document
        return try await getUser(withId: userId)
    }
    
    // MARK: - Social Features
    
    func followUser(_ targetUserId: String, currentUserId: String) async throws {
        let batch = db.batch()
        
        // Add to following collection
        let followingRef = db.collection("users").document(currentUserId)
            .collection("userFollowing").document(targetUserId)
        batch.setData(["timestamp": Timestamp()], forDocument: followingRef)
        
        // Add to followers collection
        let followerRef = db.collection("users").document(targetUserId)
            .collection("userFollowers").document(currentUserId)
        batch.setData(["timestamp": Timestamp()], forDocument: followerRef)
        
        // Update counts
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData(["followingCount": FieldValue.increment(Int64(1))], forDocument: currentUserRef)
        
        let targetUserRef = db.collection("users").document(targetUserId)
        batch.updateData(["followersCount": FieldValue.increment(Int64(1))], forDocument: targetUserRef)
        
        try await batch.commit()
    }
    
    func unfollowUser(_ targetUserId: String, currentUserId: String) async throws {
        let batch = db.batch()
        
        // Remove from following collection
        let followingRef = db.collection("users").document(currentUserId)
            .collection("userFollowing").document(targetUserId)
        batch.deleteDocument(followingRef)
        
        // Remove from followers collection
        let followerRef = db.collection("users").document(targetUserId)
            .collection("userFollowers").document(currentUserId)
        batch.deleteDocument(followerRef)
        
        // Update counts
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData(["followingCount": FieldValue.increment(Int64(-1))], forDocument: currentUserRef)
        
        let targetUserRef = db.collection("users").document(targetUserId)
        batch.updateData(["followersCount": FieldValue.increment(Int64(-1))], forDocument: targetUserRef)
        
        try await batch.commit()
    }
    
    func isFollowing(_ targetUserId: String, currentUserId: String) async throws -> Bool {
        let followingRef = db.collection("users").document(currentUserId)
            .collection("userFollowing").document(targetUserId)
        let doc = try await followingRef.getDocument()
        return doc.exists
    }
} 