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
    
    func uploadVideo(videoURL: URL, userId: String, caption: String, progressHandler: @escaping (Double) -> Void) async throws -> VideoModel {
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
        
        // Upload files using upload task for progress tracking
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = videoRef.putData(videoData, metadata: videoMetadata)
            
            // Observe upload progress
            uploadTask.observe(.progress) { snapshot in
                if let progress = snapshot.progress {
                    let fractionCompleted = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    Task { @MainActor in
                        progressHandler(fractionCompleted)
                    }
                }
            }
            
            // Handle upload completion
            uploadTask.observe(.success) { _ in
                Task {
                    do {
                        // Upload thumbnail after video upload succeeds
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
                        
                        try await self.firestoreService.uploadVideo(video)
                        continuation.resume(returning: video)
                    } catch {
                        continuation.resume(throwing: VideoUploadError.uploadFailed(error.localizedDescription))
                    }
                }
            }
            
            // Handle upload failure
            uploadTask.observe(.failure) { snapshot in
                if let error = snapshot.error {
                    continuation.resume(throwing: VideoUploadError.uploadFailed(error.localizedDescription))
                }
            }
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