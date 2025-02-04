import Foundation

struct VideoModel: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    var username: String?
    let videoUrl: String
    let caption: String
    var likes: Int
    var comments: [Comment]
    let timestamp: Date
    let thumbnailUrl: String?
    
    // Not persisted to Firestore, used for UI state
    var isLiked: Bool = false
    
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
         isLiked: Bool = false) {
        self.id = id
        self.userId = userId
        self.username = username
        self.videoUrl = videoUrl
        self.caption = caption
        self.likes = likes
        self.comments = comments
        self.timestamp = timestamp
        self.thumbnailUrl = thumbnailUrl
        self.isLiked = isLiked
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
    
    // Hashable conformance - use only id for equality
    static func == (lhs: VideoModel, rhs: VideoModel) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 