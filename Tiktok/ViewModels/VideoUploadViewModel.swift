import Foundation
import SwiftUI
import PhotosUI
import AVFoundation

@MainActor
final class VideoUploadViewModel: ObservableObject {
    @Published private(set) var isUploading = false
    @Published private(set) var uploadProgress: Double = 0
    @Published private(set) var errorMessage: String?
    @Published var caption: String = ""
    @Published var selectedVideo: PhotosPickerItem? {
        didSet {
            Task { @MainActor in
                hasSelectedVideo = selectedVideo != nil
            }
        }
    }
    @Published var hasSelectedVideo = false
    
    private let videoUploadService = VideoUploadService.shared
    
    func clearError() {
        errorMessage = nil
    }
    
    func uploadVideo(userId: String) async {
        guard let selectedVideo = selectedVideo else {
            errorMessage = "No video selected"
            return
        }
        
        do {
            isUploading = true
            errorMessage = nil
            
            guard let videoURL = try await loadVideo(from: selectedVideo) else {
                errorMessage = "Failed to load video"
                isUploading = false
                return
            }
            
            _ = try await videoUploadService.uploadVideo(
                videoURL: videoURL,
                userId: userId,
                caption: caption
            )
            
            try? FileManager.default.removeItem(at: videoURL)
            
            isUploading = false
            self.selectedVideo = nil
            caption = ""
            uploadProgress = 0
            errorMessage = nil
            
        } catch let uploadError as VideoUploadError {
            isUploading = false
            errorMessage = uploadError.localizedDescription
            print("Upload error: \(uploadError.localizedDescription)")
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
            print("Unexpected error: \(error)")
            isUploading = false
        }
    }
    
    private func loadVideo(from item: PhotosPickerItem) async throws -> URL? {
        do {
            print("DEBUG: Attempting to load video from PhotosPickerItem")
            if let videoURL = try await item.loadTransferable(type: URL.self) {
                print("DEBUG: Successfully loaded video URL: \(videoURL)")
                return videoURL
            } else {
                print("DEBUG: loadTransferable returned nil")
                
                // Try loading as Data as fallback
                print("DEBUG: Attempting to load as Data instead")
                if let videoData = try await item.loadTransferable(type: Data.self) {
                    print("DEBUG: Successfully loaded video data, creating temporary file")
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                    try videoData.write(to: tempURL)
                    print("DEBUG: Created temporary file at: \(tempURL)")
                    return tempURL
                }
                
                print("DEBUG: Both URL and Data loading attempts failed")
                throw NSError(domain: "VideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load video as URL or Data"])
            }
        } catch {
            print("DEBUG: Error loading video: \(error.localizedDescription)")
            throw error
        }
    }
} 