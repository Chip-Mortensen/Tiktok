import SwiftUI

struct VideoSearchResultsView: View {
    let isLoading: Bool
    let searchQuery: String
    let searchResults: [VideoModel]
    @Environment(\.tabSelection) var tabSelection
    @EnvironmentObject private var bookmarkService: BookmarkService
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var selectedVideo: VideoModel?

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                Text("No videos found")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1)
                    ], spacing: 1) {
                        ForEach(searchResults) { video in
                            let binding = Binding(
                                get: { video },
                                set: { _ in }  // Read-only binding since we don't need to modify it
                            )
                            NavigationLink(destination: VideoDetailView(video: binding)
                                .environmentObject(bookmarkService)
                                .environmentObject(profileViewModel)
                            ) {
                                VideoSearchThumbnailView(video: video)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct VideoSearchThumbnailView: View {
    let video: VideoModel
    
    var body: some View {
        AsyncImage(url: URL(string: video.thumbnailUrl ?? "")) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width / 3)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width / 3)
                    .clipped()
            case .failure:
                Image(systemName: "video.slash.fill")
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width / 3)
            @unknown default:
                EmptyView()
            }
        }
    }
} 