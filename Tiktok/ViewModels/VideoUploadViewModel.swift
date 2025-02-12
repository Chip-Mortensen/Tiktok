import Foundation
import SwiftUI
import PhotosUI
import AVFoundation

@MainActor
final class VideoUploadViewModel: ObservableObject {
    // Constants
    static let MAX_VIDEO_DURATION: TimeInterval = 30 * 60 // 30 minutes in seconds
    static let MAX_FILE_SIZE: Int64 = 200 * 1024 * 1024 // 200MB in bytes
    
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
            uploadProgress = 0
            
            guard let videoURL = try await loadVideo(from: selectedVideo) else {
                errorMessage = "Failed to load video"
                isUploading = false
                return
            }
            
            _ = try await videoUploadService.uploadVideo(
                videoURL: videoURL,
                userId: userId,
                caption: caption
            ) { progress in
                Task { @MainActor in
                    self.uploadProgress = progress
                }
            }
            
            try? FileManager.default.removeItem(at: videoURL)
            
            isUploading = false
            self.selectedVideo = nil
            caption = ""
            uploadProgress = 0
            errorMessage = nil
            
        } catch let uploadError as VideoUploadError {
            isUploading = false
            uploadProgress = 0
            errorMessage = uploadError.localizedDescription
            print("Upload error: \(uploadError.localizedDescription)")
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
            print("Unexpected error: \(error)")
            isUploading = false
            uploadProgress = 0
        }
    }
    
    private func loadVideo(from item: PhotosPickerItem) async throws -> URL? {
        do {
            print("DEBUG: Attempting to load video from PhotosPickerItem")
            if let videoURL = try await item.loadTransferable(type: URL.self) {
                print("DEBUG: Successfully loaded video URL: \(videoURL)")
                return try await validateVideo(at: videoURL)
            } else {
                print("DEBUG: loadTransferable returned nil")
                
                // Try loading as Data as fallback
                print("DEBUG: Attempting to load as Data instead")
                if let videoData = try await item.loadTransferable(type: Data.self) {
                    print("DEBUG: Successfully loaded video data, creating temporary file")
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                    try videoData.write(to: tempURL)
                    print("DEBUG: Created temporary file at: \(tempURL)")
                    return try await validateVideo(at: tempURL)
                }
                
                print("DEBUG: Both URL and Data loading attempts failed")
                throw VideoUploadError.pickerLoadFailed
            }
        } catch {
            print("DEBUG: Error loading video: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func validateVideo(at url: URL) async throws -> URL {
        print("DEBUG: Validating video at \(url)")
        
        // Check format
        guard url.pathExtension.lowercased() == "mp4" else {
            print("DEBUG: Invalid format")
            throw VideoUploadError.invalidFormat
        }
        
        // Check duration
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationInSeconds = duration.seconds
        
        guard durationInSeconds <= Self.MAX_VIDEO_DURATION else {
            print("DEBUG: Duration exceeds limit")
            throw VideoUploadError.videoDurationExceeded(durationInSeconds)
        }
        
        // Check file size
        let resources = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = resources.fileSize ?? 0
        
        guard Int64(fileSize) <= Self.MAX_FILE_SIZE else {
            print("DEBUG: File size exceeds limit")
            throw VideoUploadError.fileSizeExceeded(Int64(fileSize))
        }
        
        print("DEBUG: Video validation successful")
        return url
    }
} 