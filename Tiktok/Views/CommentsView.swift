import SwiftUI

struct CommentsView: View {
    @StateObject var viewModel: CommentsViewModel
    @State private var newCommentText: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Comments")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                }
            }
            .padding()
            
            Divider()
            
            // Comments List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if viewModel.comments.isEmpty {
                        Text("No comments yet. Be the first to comment!")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(viewModel.comments) { comment in
                            CommentCell(comment: comment)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            
            Divider()
            
            // Comment Input
            HStack(spacing: 12) {
                TextField("Add a comment...", text: $newCommentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button {
                    Task {
                        await viewModel.postComment(text: newCommentText)
                        newCommentText = ""
                    }
                } label: {
                    if viewModel.isPosting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Post")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPosting)
            }
            .padding()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }
}

struct CommentCell: View {
    let comment: CommentModel
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // User Avatar
            if let profileImageUrl = comment.profileImageUrl,
               let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.gray)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Username and timestamp
                HStack {
                    Text(comment.username ?? "user")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("·")
                        .foregroundColor(.gray)
                    
                    Text(comment.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Comment text
                Text(comment.text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
    }
}

#Preview {
    CommentsView(viewModel: CommentsViewModel(videoId: "previewVideoId"))
} 