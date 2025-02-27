import SwiftUI

struct VideoGridView: View {
    @Binding var videos: [VideoModel]
    let onVideoTap: (VideoModel) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, _ in
                    VideoThumbnailView(video: $videos[index]) {
                        onVideoTap(videos[index])
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.top, 4) // Just a tiny bit of space between tabs and grid
        }
        .background(Color(.systemBackground))
    }
} 