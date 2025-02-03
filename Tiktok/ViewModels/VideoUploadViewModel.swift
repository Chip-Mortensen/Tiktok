import Foundation
import SwiftUI
import PhotosUI
import AVFoundation

@MainActor
class VideoUploadViewModel: ObservableObject {
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var selectedVideo: PhotosPickerItem? = nil
    @Published var caption: String = ""
    
    private let videoUploadService = VideoUploadService.shared
    
    func uploadVideo(userId: String) async {
        guard let selectedVideo = selectedVideo else {
            errorMessage = "No video selected"
            return
        }
        
        do {
            isUploading = true
            errorMessage = nil
            
            // Load video data from PhotosPickerItem
            guard let videoURL = try await loadVideo(from: selectedVideo) else {
                errorMessage = "Failed to load video"
                isUploading = false
                return
            }
            
            // Upload video
            _ = try await videoUploadService.uploadVideo(
                videoURL: videoURL,
                userId: userId,
                caption: caption
            )
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: videoURL)
            
            // Reset state
            isUploading = false
            self.selectedVideo = nil
            caption = ""
            uploadProgress = 0
            
        } catch let uploadError as VideoUploadError {
            isUploading = false
            errorMessage = uploadError.localizedDescription
            print("Video upload error: \(uploadError.localizedDescription)")
        } catch {
            isUploading = false
            errorMessage = "Unexpected error: \(error.localizedDescription)"
            print("Unexpected error: \(error)")
        }
    }
    
    private func loadVideo(from item: PhotosPickerItem) async throws -> URL? {
        if let videoData = try await item.loadTransferable(type: Data.self) {
            // Create temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try videoData.write(to: tempURL)
            return tempURL
        }
        return nil
    }
} 