import Foundation
import FirebaseFirestore

// Nonisolated type to manage listeners
private enum ListenerStore {
    private static var activeListeners: [String: ListenerRegistration] = [:]
    
    static func store(_ listener: ListenerRegistration, for key: String) {
        activeListeners[key] = listener
    }
    
    static func remove(for key: String) {
        activeListeners[key]?.remove()
        activeListeners[key] = nil
    }
}

@MainActor
class CommentsViewModel: ObservableObject {
    @Published var comments: [CommentModel] = []
    @Published var errorMessage: String?
    @Published var isPosting = false
    
    private let firestoreService = FirestoreService.shared
    let videoId: String
    
    init(videoId: String) {
        self.videoId = videoId
        setupCommentsListener()
    }
    
    deinit {
        removeListener()
    }
    
    func setupCommentsListener() {
        // Remove any existing listener first
        removeListener()
        
        // Setup new listener
        let newListener = firestoreService.addCommentsListener(forVideoId: videoId) { [weak self] comments in
            Task { @MainActor in
                self?.comments = comments
            }
        }
        
        // Store the listener
        ListenerStore.store(newListener, for: videoId)
    }
    
    nonisolated func removeListener() {
        ListenerStore.remove(for: videoId)
    }
    
    func postComment(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPosting = true
        do {
            try await firestoreService.addComment(videoId: videoId, text: text)
            // No need to fetch comments manually as the listener will update them
        } catch {
            errorMessage = error.localizedDescription
            print("DEBUG: Failed to post comment: \(error.localizedDescription)")
        }
        isPosting = false
    }
} 