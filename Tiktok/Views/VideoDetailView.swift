import SwiftUI

struct VideoDetailView: View {
    @Binding var video: VideoModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: ProfileViewModel
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VideoContent(video: $video, isActive: true)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .font(.title2)
                }
            }
        }
    }
} 