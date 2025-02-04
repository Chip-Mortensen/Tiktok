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
        let videoId = UUID().uuidString
        let videoRef = storage.child("videos/\(userId)/\(videoId).mp4")
        let thumbnailRef = storage.child("thumbnails/\(userId)/\(videoId).jpg")
        
        // Get username
        let username = try await firestoreService.getUsernameForUserId(userId)
        
        // Generate thumbnail
        guard let thumbnail = try await generateThumbnail(from: videoURL),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) else {
            throw VideoUploadError.thumbnailGenerationFailed
        }
        
        // Read video data
        guard let videoData = try? Data(contentsOf: videoURL) else {
            throw VideoUploadError.videoDataReadFailed
        }
        
        // Set metadata
        let videoMetadata = StorageMetadata()
        videoMetadata.contentType = "video/mp4"
        
        let thumbnailMetadata = StorageMetadata()
        thumbnailMetadata.contentType = "image/jpeg"
        
        // Upload files using putDataAsync
        do {
            let _ = try await videoRef.putDataAsync(videoData, metadata: videoMetadata)
            let _ = try await thumbnailRef.putDataAsync(thumbnailData, metadata: thumbnailMetadata)
            
            // Get download URLs
            let finalVideoURL = try await videoRef.downloadURL()
            let finalThumbnailURL = try await thumbnailRef.downloadURL()
            
            let video = VideoModel(
                id: videoId,
                userId: userId,
                username: username,
                videoUrl: finalVideoURL.absoluteString,
                caption: caption,
                thumbnailUrl: finalThumbnailURL.absoluteString
            )
            
            try await firestoreService.uploadVideo(video)
            return video
        } catch {
            throw VideoUploadError.uploadFailed(error.localizedDescription)
        }
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        return try await withCheckedThrowingContinuation { continuation in
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, image, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: UIImage(cgImage: image))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// Extension to help with async thumbnail generation
extension AVAssetImageGenerator {
    func image(at time: CMTime) async throws -> (image: CGImage, actualTime: CMTime) {
        try await withCheckedThrowingContinuation { continuation in
            generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: (image, time))
                } else {
                    continuation.resume(throwing: VideoUploadError.thumbnailGenerationFailed)
                }
            }
        }
    }
} 