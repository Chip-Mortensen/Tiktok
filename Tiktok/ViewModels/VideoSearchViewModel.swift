import SwiftUI
import FirebaseFirestore

@MainActor
class VideoSearchViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [VideoModel] = []
    @Published var isLoading = false
    private let db = Firestore.firestore()
    private var searchTask: Task<Void, Never>?

    func performSearch() {
        // Cancel any previous task
        searchTask?.cancel()

        // Check that the query is not empty
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            self.searchResults = []
            self.isLoading = false
            return
        }

        isLoading = true

        searchTask = Task {
            // Debounce typing
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            do {
                // Get all videos and filter in memory (temporary solution)
                let snapshot = try await db.collection("videos")
                    .order(by: "timestamp", descending: true)
                    .limit(to: 50)
                    .getDocuments()

                var videos: [VideoModel] = []
                let searchTermLower = trimmedQuery.lowercased()

                for document in snapshot.documents {
                    let data = document.data()
                    let transcription = (data["transcription"] as? String ?? "").lowercased()
                    let caption = (data["caption"] as? String ?? "").lowercased()
                    
                    // Check if either field contains the search term
                    if transcription.contains(searchTermLower) || caption.contains(searchTermLower) {
                        let video = VideoModel(
                            id: document.documentID,
                            userId: data["userId"] as? String ?? "",
                            username: data["username"] as? String,
                            videoUrl: data["videoUrl"] as? String ?? "",
                            caption: data["caption"] as? String ?? "",
                            likes: data["likes"] as? Int ?? 0,
                            comments: [],
                            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                            thumbnailUrl: data["thumbnailUrl"] as? String,
                            m3u8Url: data["m3u8Url"] as? String,
                            isLiked: false,
                            isBookmarked: false,
                            commentsCount: data["commentsCount"] as? Int ?? 0,
                            segments: nil
                        )
                        videos.append(video)
                    }
                }

                // Update UI on main thread
                await MainActor.run {
                    self.searchResults = videos
                    self.isLoading = false
                }

                // Print debug information
                print("Search query: \(trimmedQuery)")
                print("Found \(videos.count) videos")
                print("Total videos checked: \(snapshot.documents.count)")
                if !videos.isEmpty {
                    print("Sample matching transcription: \(snapshot.documents.first?["transcription"] as? String ?? "No transcription")")
                }
            } catch {
                print("Video search error: \(error.localizedDescription)")
                await MainActor.run {
                    self.searchResults = []
                    self.isLoading = false
                }
            }
        }
    }
} 