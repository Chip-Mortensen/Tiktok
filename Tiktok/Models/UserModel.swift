import Foundation

struct UserModel: Identifiable, Codable {
    let id: String
    let username: String
    let email: String
    var profileImageUrl: String?
    var bio: String?
    var followers: Int
    var following: Int
    var videosCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case profileImageUrl
        case bio
        case followers
        case following
        case videosCount
    }
    
    init(id: String = UUID().uuidString,
         username: String,
         email: String,
         profileImageUrl: String? = nil,
         bio: String? = nil,
         followers: Int = 0,
         following: Int = 0,
         videosCount: Int = 0) {
        self.id = id
        self.username = username
        self.email = email
        self.profileImageUrl = profileImageUrl
        self.bio = bio
        self.followers = followers
        self.following = following
        self.videosCount = videosCount
    }
} 