import Foundation
import FirebaseFirestore
import Combine

@MainActor
class CommentsCountViewModel: ObservableObject {
    @Published var count: Int = 0
    private var listener: ListenerRegistration?
    private let firestoreService = FirestoreService.shared
    let videoId: String
    
    init(videoId: String) {
        self.videoId = videoId
        listenForCommentsCount()
    }
    
    deinit {
        listener?.remove()
    }
    
    private func listenForCommentsCount() {
        // Use the existing comments listener and update the count based on the number of comment documents.
        listener = firestoreService.addCommentsListener(forVideoId: videoId) { [weak self] comments in
            self?.count = comments.count
        }
    }
} 