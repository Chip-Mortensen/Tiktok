import SwiftUI
import PhotosUI

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.tabSelection) private var tabSelection
    
    var body: some View {
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
            let hasVideo = viewModel.hasSelectedVideo
            
            PhotosPicker(
                selection: $viewModel.selectedVideo,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                if hasVideo {
                    Label("Video Selected", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(Color(.systemGreen).opacity(0.2))
                        .cornerRadius(12)
                } else {
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
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            await MainActor.run {
                                viewModel.clearError()
                            }
                        }
                    }
            }
            
            // Upload Button
            let isUploading = viewModel.isUploading
            
            UploadButton(
                isUploading: isUploading,
                hasSelectedVideo: hasVideo
            ) {
                guard let userId = authViewModel.user?.id else {
                    viewModel.clearError()
                    return
                }
                
                Task {
                    await viewModel.uploadVideo(userId: userId)
                    await MainActor.run {
                        if viewModel.errorMessage == nil {
                            tabSelection.wrappedValue = 0 // Switch to home tab after successful upload
                        }
                    }
                }
            }
            .disabled(!hasVideo || isUploading)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top)
    }
}

// Separate component to handle button styling
struct UploadButton: View {
    let isUploading: Bool
    let hasSelectedVideo: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(isUploading ? "Uploading..." : "Upload Video")
                    .fontWeight(.semibold)
                if isUploading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(hasSelectedVideo ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(15)
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