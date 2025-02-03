import SwiftUI
import PhotosUI

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 25) {
                // Logo/Title
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    Text("Upload Video")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.bottom, 40)
                
                // Video Picker
                PhotosPicker(
                    selection: $viewModel.selectedVideo,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    if viewModel.selectedVideo == nil {
                        VStack {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 40))
                            Text("Select Video")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else {
                        Label("Video Selected", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Color(.systemGreen).opacity(0.2))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Caption TextField
                TextField("Add a caption...", text: $viewModel.caption)
                    .textFieldStyle(CustomTextFieldStyle())
                    .padding(.horizontal)
                    .disabled(viewModel.isUploading)
                
                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Upload Button
                Button {
                    guard let userId = authViewModel.user?.id else {
                        viewModel.errorMessage = "User not logged in"
                        return
                    }
                    
                    Task {
                        await viewModel.uploadVideo(userId: userId)
                        if viewModel.errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.isUploading ? "Uploading..." : "Upload Video")
                            .fontWeight(.semibold)
                        if viewModel.isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.selectedVideo == nil ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .disabled(viewModel.selectedVideo == nil || viewModel.isUploading)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isUploading)
                }
            }
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
} 