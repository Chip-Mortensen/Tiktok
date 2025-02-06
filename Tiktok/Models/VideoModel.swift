import Foundation

struct VideoModel: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    var username: String?
    let videoUrl: String
    var caption: String
    var likes: Int
    var comments: [Comment]
    var commentsCount: Int
    let timestamp: Date
    var thumbnailUrl: String?
    var m3u8Url: String?
    
    // Not persisted to Firestore, used for UI state
    var isLiked: Bool = false
    var isBookmarked: Bool = false
    
    struct Comment: Identifiable, Codable, Hashable {
        let id: String
        let userId: String
        let text: String
        let timestamp: Date
        
        init(id: String = UUID().uuidString,
             userId: String,
             text: String,
             timestamp: Date = Date()) {
            self.id = id
            self.userId = userId
            self.text = text
            self.timestamp = timestamp
        }
    }
    
    init(id: String = UUID().uuidString,
         userId: String,
         username: String?,
         videoUrl: String,
         caption: String,
         likes: Int = 0,
         comments: [Comment] = [],
         timestamp: Date = Date(),
         thumbnailUrl: String? = nil,
         m3u8Url: String? = nil,
         isLiked: Bool = false,
         isBookmarked: Bool = false,
         commentsCount: Int = 0) {
        self.id = id
        self.userId = userId
        self.username = username
        self.videoUrl = videoUrl
        self.caption = caption
        self.likes = likes
        self.comments = comments
        self.timestamp = timestamp
        self.thumbnailUrl = thumbnailUrl
        self.m3u8Url = m3u8Url
        self.isLiked = isLiked
        self.isBookmarked = isBookmarked
        self.commentsCount = commentsCount
    }
    
    // Mutating functions for state updates
    mutating func like() {
        likes += 1
        isLiked = true
    }
    
    mutating func unlike() {
        likes -= 1
        isLiked = false
    }
    
    mutating func bookmark() {
        isBookmarked = true
    }
    
    mutating func unbookmark() {
        isBookmarked = false
    }
    
    // Hashable conformance - use only id for equality
    static func == (lhs: VideoModel, rhs: VideoModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.isLiked == rhs.isLiked &&
        lhs.likes == rhs.likes &&
        lhs.isBookmarked == rhs.isBookmarked
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 