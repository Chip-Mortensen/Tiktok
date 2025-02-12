import SwiftUI

struct VideoSearchResultsView: View {
    let isLoading: Bool
    let searchQuery: String
    let searchResults: [(video: VideoModel, startTime: Double?)]
    @Environment(\.tabSelection) var tabSelection
    @EnvironmentObject private var bookmarkService: BookmarkService
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var selectedVideo: VideoModel?

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

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
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(searchResults, id: \.video.id) { result in
                            let binding = Binding(
                                get: { result.video },
                                set: { _ in }  // Read-only binding since we don't need to modify it
                            )
                            NavigationLink(destination: VideoDetailView(video: binding, initialStartTime: result.startTime)
                                .environmentObject(bookmarkService)
                                .environmentObject(profileViewModel)
                            ) {
                                VideoSearchThumbnailView(video: result.video)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.top, 4) // Just a tiny bit of space between tabs and grid
                }
                .background(Color(.systemBackground))
            }
        }
    }
}

private struct VideoSearchThumbnailView: View {
    let video: VideoModel
    @EnvironmentObject private var bookmarkService: BookmarkService
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailUrl ?? "")) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            ProgressView()
                        }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .clipped()
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            
            // Overlay with likes and bookmarks
            HStack {
                // Likes
                HStack {
                    Image(systemName: video.isLiked ? "heart.fill" : "heart")
                        .foregroundColor(video.isLiked ? .red : .white)
                    Text("\(video.likes)")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                
                // Bookmarks
                if bookmarkService.bookmarkedVideoIds.contains(video.id) {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.5))
            .cornerRadius(6)
            .padding(8)
        }
        .aspectRatio(9/16, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
} 