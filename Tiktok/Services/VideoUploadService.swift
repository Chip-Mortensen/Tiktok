import Foundation
import FirebaseStorage
import AVFoundation
import UIKit

enum VideoUploadError: Error {
    case thumbnailGenerationFailed
    case videoDataReadFailed
    case uploadFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .videoDataReadFailed:
            return "Failed to read video data"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        }
    }
}

actor VideoUploadService {
    static let shared = VideoUploadService()
    private let storage = Storage.storage().reference()
    private let firestoreService = FirestoreService.shared
    
    private init() {}
    
    func uploadVideo(videoURL: URL, userId: String, caption: String) async throws -> VideoModel {
        print("Starting video upload process...")
        print("Video URL to upload: \(videoURL)")
        
        // Generate a unique ID for the video
        let videoId = UUID().uuidString
        print("Generated video ID: \(videoId)")
        
        // Create storage references
        let videoRef = storage.child("videos/\(userId)/\(videoId).mp4")
        let thumbnailRef = storage.child("thumbnails/\(userId)/\(videoId).jpg")
        print("Storage paths created - Video: \(videoRef.fullPath), Thumbnail: \(thumbnailRef.fullPath)")
        
        // Generate thumbnail
        print("Generating thumbnail...")
        let thumbnail = try await generateThumbnail(from: videoURL)
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) else {
            throw VideoUploadError.thumbnailGenerationFailed
        }
        print("Thumbnail generated successfully")
        
        // Upload thumbnail
        print("Uploading thumbnail...")
        let thumbnailMetadata = StorageMetadata()
        thumbnailMetadata.contentType = "image/jpeg"
        
        // Upload thumbnail with retry
        var thumbnailUploadAttempts = 0
        var thumbnailURL: URL?
        while thumbnailUploadAttempts < 3 && thumbnailURL == nil {
            do {
                thumbnailUploadAttempts += 1
                print("Starting thumbnail upload attempt \(thumbnailUploadAttempts)...")
                
                // Upload the thumbnail data
                _ = try await thumbnailRef.putData(thumbnailData, metadata: thumbnailMetadata)
                print("Thumbnail data uploaded successfully")
                
                // Add a small delay before getting the download URL
                try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                
                print("Getting thumbnail download URL...")
                thumbnailURL = try await thumbnailRef.downloadURL()
                print("Thumbnail uploaded successfully to: \(thumbnailURL?.absoluteString ?? "")")
                break // Exit loop on success
            } catch {
                print("Thumbnail upload attempt \(thumbnailUploadAttempts) failed: \(error.localizedDescription)")
                if thumbnailUploadAttempts == 3 {
                    throw VideoUploadError.uploadFailed("Failed to upload thumbnail after 3 attempts")
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second before retry
            }
        }
        
        guard let finalThumbnailURL = thumbnailURL else {
            throw VideoUploadError.uploadFailed("Failed to get thumbnail URL")
        }
        
        // Upload video
        print("Reading video data...")
        guard let videoData = try? Data(contentsOf: videoURL) else {
            throw VideoUploadError.videoDataReadFailed
        }
        print("Video data read successfully: \(ByteCountFormatter.string(fromByteCount: Int64(videoData.count), countStyle: .file))")
        
        print("Uploading video data...")
        let videoMetadata = StorageMetadata()
        videoMetadata.contentType = "video/mp4"
        
        // Upload video with retry
        var videoUploadAttempts = 0
        var finalVideoURL: URL?
        while videoUploadAttempts < 3 && finalVideoURL == nil {
            do {
                videoUploadAttempts += 1
                print("Starting video upload attempt \(videoUploadAttempts)...")
                
                // Upload the video data
                _ = try await videoRef.putData(videoData, metadata: videoMetadata)
                print("Video data uploaded successfully")
                
                // Add a small delay before getting the download URL
                try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                
                print("Getting download URL...")
                finalVideoURL = try await videoRef.downloadURL()
                print("Video uploaded successfully, URL: \(finalVideoURL?.absoluteString ?? "")")
                break // Exit loop on success
            } catch {
                print("Video upload attempt \(videoUploadAttempts) failed: \(error.localizedDescription)")
                if videoUploadAttempts == 3 {
                    throw VideoUploadError.uploadFailed("Failed to upload video after 3 attempts")
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second before retry
            }
        }
        
        guard let videoDownloadURL = finalVideoURL else {
            throw VideoUploadError.uploadFailed("Failed to get video URL")
        }
        
        // Create video model
        print("Creating video model...")
        let video = VideoModel(
            id: videoId,
            userId: userId,
            videoUrl: videoDownloadURL.absoluteString,
            caption: caption,
            thumbnailUrl: finalThumbnailURL.absoluteString
        )
        
        // Save to Firestore
        print("Saving to Firestore...")
        try await firestoreService.uploadVideo(video)
        print("Video upload process completed successfully")
        
        return video
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> UIImage {
        print("Starting thumbnail generation from URL: \(videoURL)")
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            print("Thumbnail generated successfully")
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ Error generating thumbnail: \(error.localizedDescription)")
            throw VideoUploadError.thumbnailGenerationFailed
        }
    }
}

// Extension to help with async thumbnail generation
extension AVAssetImageGenerator {
    func image(at time: CMTime) async throws -> (image: CGImage, actualTime: CMTime) {
        try await withCheckedThrowingContinuation { continuation in
            self.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cgImage = cgImage {
                    continuation.resume(returning: (cgImage, time))
                } else {
                    continuation.resume(throwing: VideoUploadError.thumbnailGenerationFailed)
                }
            }
        }
    }
} 