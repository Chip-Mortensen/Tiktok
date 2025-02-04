import Foundation
import FirebaseFirestore

struct CommentModel: Identifiable, Codable {
    var id: String = UUID().uuidString
    let videoId: String
    let userId: String
    let text: String
    let timestamp: Date
    var username: String?
    var profileImageUrl: String?
    
    // Initializer from Firestore document
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let videoId = data["videoId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
            return nil
        }
        self.id = document.documentID
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.username = data["username"] as? String
        self.profileImageUrl = data["profileImageUrl"] as? String
    }
    
    // Convert to Firestore dictionary
    func toDictionary() -> [String: Any] {
        let dict: [String: Any] = [
            "videoId": videoId,
            "userId": userId,
            "text": text,
            "timestamp": Timestamp(date: timestamp),
            "username": username as Any,
            "profileImageUrl": profileImageUrl as Any
        ]
        return dict
    }
} 