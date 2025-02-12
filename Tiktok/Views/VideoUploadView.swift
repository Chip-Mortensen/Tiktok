import SwiftUI
import PhotosUI
import AVKit

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.tabSelection) private var tabSelection
    @State private var showingGuidelines = false
    @State private var previewPlayer: AVPlayer?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Header Section
                VStack(spacing: 8) {
                    Text("Create New Video")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Share knowledge that matters, in minutes")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                
                // Video Picker
                PhotosPicker(
                    selection: $viewModel.selectedVideo,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    ZStack {
                        if viewModel.hasSelectedVideo {
                            if let previewPlayer = previewPlayer {
                                VideoPlayer(player: previewPlayer)
                                    .frame(width: 200, height: 300)
                                    .cornerRadius(15)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15)
                                            .stroke(Color.blue, lineWidth: 2)
                                    )
                            } else {
                                Rectangle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 200, height: 300)
                                    .cornerRadius(15)
                                    .overlay(
                                        ProgressView()
                                    )
                            }
                        } else {
                            VStack(spacing: 16) {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "video.badge.plus")
                                            .font(.system(size: 30))
                                            .foregroundColor(.blue)
                                    )
                                
                                Text("Tap to Select Video")
                                    .font(.headline)
                                
                                Text("MP4 format • Max 30 minutes • Max 200MB")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 200, height: 300)
                            .background(Color(.systemGray6))
                            .cornerRadius(15)
                        }
                    }
                }
                
                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                        )
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(4))
                                withAnimation(.easeOut(duration: 0.3)) {
                                    viewModel.clearError()
                                }
                            }
                        }
                }
                
                // Caption Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Caption")
                        .font(.headline)
                    
                    TextEditor(text: $viewModel.caption)
                        .frame(height: 100)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .disabled(viewModel.isUploading)
                        .overlay(alignment: .topLeading) {
                            if viewModel.caption.isEmpty {
                                Text("Describe your content to help others find it...")
                                    .foregroundColor(Color(.placeholderText))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.horizontal, 24)
                
                // Guidelines Button
                Button {
                    showingGuidelines = true
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Upload Guidelines")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                
                // Upload Progress
                if viewModel.isUploading {
                    VStack(spacing: 12) {
                        ProgressView(value: viewModel.uploadProgress, total: 1.0)
                            .progressViewStyle(CustomUploadProgressStyle())
                            .padding(.horizontal)
                        
                        Text("\(Int(viewModel.uploadProgress * 100))% uploaded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical)
                }
                
                // Upload Button
                Button {
                    guard let userId = authViewModel.user?.id else {
                        viewModel.clearError()
                        return
                    }
                    
                    Task {
                        await viewModel.uploadVideo(userId: userId)
                        await MainActor.run {
                            if viewModel.errorMessage == nil {
                                tabSelection.wrappedValue = 0
                            }
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 8)
                        }
                        Text(viewModel.isUploading ? "Uploading..." : "Share Video")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.hasSelectedVideo ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .disabled(!viewModel.hasSelectedVideo || viewModel.isUploading)
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        .sheet(isPresented: $showingGuidelines) {
            GuidelinesView()
        }
        .onChange(of: viewModel.selectedVideo) { _, _ in
            setupPreviewPlayer()
        }
    }
    
    private func setupPreviewPlayer() {
        // Clean up existing player
        previewPlayer?.pause()
        previewPlayer = nil
        
        Task {
            if let videoData = try? await viewModel.selectedVideo?.loadTransferable(type: Data.self),
               let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("preview.mov") {
                try? videoData.write(to: url)
                await MainActor.run {
                    previewPlayer = AVPlayer(url: url)
                    previewPlayer?.play()
                }
            }
        }
    }
}

struct CustomUploadProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue)
                    .frame(width: CGFloat(configuration.fractionCompleted ?? 0) * geometry.size.width, height: 8)
            }
        }
        .frame(height: 8)
    }
}

struct GuidelinesView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    GuidelineRow(icon: "video", title: "Video Requirements", description: "MP4 format, max 30 minutes long, max 200MB file size")
                    GuidelineRow(icon: "rectangle.and.text.magnifyingglass", title: "Content Quality", description: "Clear, well-lit videos with good audio quality")
                    GuidelineRow(icon: "exclamationmark.triangle", title: "Content Guidelines", description: "No explicit, harmful, or copyrighted content")
                    GuidelineRow(icon: "person.2", title: "Community Standards", description: "Share informative, educational content that adds value")
                }
            }
            .navigationTitle("Upload Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GuidelineRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
} 