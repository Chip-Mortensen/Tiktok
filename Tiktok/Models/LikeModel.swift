import Foundation
import FirebaseFirestore

struct LikeModel: Identifiable {
    let id: String
    let userId: String
    let videoId: String
    let timestamp: Date
    var username: String?
    var profileImageUrl: String?
    
    init?(document: QueryDocumentSnapshot) {
        self.id = document.documentID
        
        guard let userId = document.data()["userId"] as? String,
              let videoId = document.data()["videoId"] as? String,
              let timestamp = (document.data()["timestamp"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.userId = userId
        self.videoId = videoId
        self.timestamp = timestamp
    }
} 