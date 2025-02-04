import SwiftUI

struct VideoThumbnailView: View {
    @Binding var video: VideoModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
                if let thumbnailUrl = video.thumbnailUrl,
                   let url = URL(string: thumbnailUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay {
                                ProgressView()
                            }
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                }
                
                // Overlay with likes count
                HStack {
                    Image(systemName: video.isLiked ? "heart.fill" : "heart")
                        .foregroundColor(video.isLiked ? .red : .white)
                    Text("\(video.likes)")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .padding(8)
                .shadow(radius: 2)
            }
        }
        .aspectRatio(9/16, contentMode: .fill)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
} 