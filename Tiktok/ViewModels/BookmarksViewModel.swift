import SwiftUI
import FirebaseAuth

@MainActor
class BookmarksViewModel: ObservableObject {
    @Published var videos: [VideoModel] = []
    @Published var selectedVideo: VideoModel?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let bookmarkService = BookmarkService.shared
    
    func fetchBookmarkedVideos() async {
        isLoading = true
        error = nil
        
        do {
            videos = try await bookmarkService.fetchBookmarkedVideos()
        } catch {
            self.error = error
            print("DEBUG: Error fetching bookmarked videos: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func updateVideo(_ video: VideoModel) {
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index] = video
        }
    }
} 