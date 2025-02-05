import SwiftUI

struct BookmarksView: View {
    @StateObject private var viewModel = BookmarksViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.videos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("No bookmarks yet")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        VideoGridView(videos: $viewModel.videos) { video in
                            viewModel.selectedVideo = video
                        }
                        .padding(.top)
                    }
                }
            }
            .navigationDestination(item: $viewModel.selectedVideo) { video in
                VideoDetailView(video: Binding(
                    get: { video },
                    set: { newValue in
                        viewModel.updateVideo(newValue)
                        viewModel.selectedVideo = newValue
                    }
                ))
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.fetchBookmarkedVideos()
        }
    }
}

#Preview {
    BookmarksView()
} 