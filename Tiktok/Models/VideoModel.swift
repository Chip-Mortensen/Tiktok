import Foundation

struct VideoModel: Identifiable, Codable {
    let id: String
    let userId: String
    let videoUrl: String
    let caption: String
    var likes: Int
    var comments: [Comment]
    let timestamp: Date
    var thumbnailUrl: String?
    
    struct Comment: Identifiable, Codable {
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
         videoUrl: String,
         caption: String,
         likes: Int = 0,
         comments: [Comment] = [],
         timestamp: Date = Date(),
         thumbnailUrl: String? = nil) {
        self.id = id
        self.userId = userId
        self.videoUrl = videoUrl
        self.caption = caption
        self.likes = likes
        self.comments = comments
        self.timestamp = timestamp
        self.thumbnailUrl = thumbnailUrl
    }
} 