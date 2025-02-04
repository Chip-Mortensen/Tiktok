import SwiftUI

struct EditVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    let video: VideoModel
    let onSave: (VideoModel) async -> Bool

    init(video: VideoModel, onSave: @escaping (VideoModel) async -> Bool) {
        self.video = video
        self._caption = State(initialValue: video.caption)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Caption")) {
                    TextField("Enter caption", text: $caption)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Video")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            let updatedVideo = videoWithNewCaption
                            if await onSave(updatedVideo) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var videoWithNewCaption: VideoModel {
        VideoModel(
            id: video.id,
            userId: video.userId,
            username: video.username,
            videoUrl: video.videoUrl,
            caption: caption,
            likes: video.likes,
            comments: video.comments,
            timestamp: video.timestamp,
            thumbnailUrl: video.thumbnailUrl
        )
    }
}

struct EditVideoView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleVideo = VideoModel(
            id: "video123",
            userId: "user123",
            username: "tester",
            videoUrl: "https://example.com/video.mp4",
            caption: "My original caption",
            likes: 10,
            comments: [],
            timestamp: Date(),
            thumbnailUrl: nil
        )
        EditVideoView(video: sampleVideo) { updatedVideo in
            // preview save returns success immediately
            return true
        }
    }
} 