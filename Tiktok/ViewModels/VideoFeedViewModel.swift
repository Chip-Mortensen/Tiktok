import Foundation

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [VideoModel] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firestoreService = FirestoreService.shared
    
    func fetchVideos() async {
        isLoading = true
        error = nil
        
        do {
            videos = try await firestoreService.fetchVideos()
        } catch {
            self.error = error.localizedDescription
            print("Error fetching videos: \(error)")
        }
        
        isLoading = false
    }
} 