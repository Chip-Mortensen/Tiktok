import Foundation

enum UserListSheetType: Identifiable {
    case followers
    case following
    case likes
    
    var id: String {
        switch self {
        case .followers: return "followers"
        case .following: return "following"
        case .likes: return "likes"
        }
    }
    
    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        case .likes: return "Likes"
        }
    }
} 