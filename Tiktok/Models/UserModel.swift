import Foundation
import FirebaseFirestore

struct UserModel: Identifiable, Codable {
    var id: String?
    let email: String
    var username: String
    var profileImageUrl: String?
    var bio: String?
    var followingCount: Int
    var followersCount: Int
    var likesCount: Int
    var postsCount: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case profileImageUrl
        case bio
        case followingCount
        case followersCount
        case likesCount
        case postsCount
        case createdAt
    }
    
    init(id: String? = nil,
         email: String,
         username: String,
         profileImageUrl: String? = nil,
         bio: String? = nil,
         followingCount: Int = 0,
         followersCount: Int = 0,
         likesCount: Int = 0,
         postsCount: Int = 0,
         createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.username = username
        self.profileImageUrl = profileImageUrl
        self.bio = bio
        self.followingCount = followingCount
        self.followersCount = followersCount
        self.likesCount = likesCount
        self.postsCount = postsCount
        self.createdAt = createdAt
    }
    
    // Add initializer from Firestore document
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        
        guard let email = data["email"] as? String,
              let username = data["username"] as? String else {
            return nil
        }
        
        self.id = document.documentID
        self.email = email
        self.username = username
        self.profileImageUrl = data["profileImageUrl"] as? String
        self.bio = data["bio"] as? String
        self.followingCount = data["followingCount"] as? Int ?? 0
        self.followersCount = data["followersCount"] as? Int ?? 0
        self.likesCount = data["likesCount"] as? Int ?? 0
        self.postsCount = data["postsCount"] as? Int ?? 0
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
    
    // Convert to Firestore data
    func toDictionary() -> [String: Any] {
        return [
            "email": email,
            "username": username,
            "profileImageUrl": profileImageUrl as Any,
            "bio": bio as Any,
            "followingCount": followingCount,
            "followersCount": followersCount,
            "likesCount": likesCount,
            "postsCount": postsCount,
            "createdAt": Timestamp(date: createdAt)
        ]
    }
} 