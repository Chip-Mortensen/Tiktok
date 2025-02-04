import Foundation
import FirebaseFirestore

@MainActor
class CommentsViewModel: ObservableObject {
    @Published var comments: [CommentModel] = []
    @Published var errorMessage: String?
    @Published var isPosting = false
    
    private let firestoreService = FirestoreService.shared
    private var listener: ListenerRegistration?
    let videoId: String
    
    init(videoId: String) {
        self.videoId = videoId
        setupCommentsListener()
    }
    
    deinit {
        listener?.remove()
    }
    
    private func setupCommentsListener() {
        listener = firestoreService.addCommentsListener(forVideoId: videoId) { [weak self] comments in
            self?.comments = comments
        }
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