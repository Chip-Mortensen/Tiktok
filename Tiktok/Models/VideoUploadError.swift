import Foundation

public enum VideoUploadError: Error {
    case thumbnailGenerationFailed
    case videoDataReadFailed
    case uploadFailed(String)
    case videoDurationExceeded(TimeInterval)
    case fileSizeExceeded(Int64)
    case invalidFormat
    case pickerLoadFailed
    
    public var localizedDescription: String {
        switch self {
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .videoDataReadFailed:
            return "Failed to read video data"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .videoDurationExceeded(let duration):
            return "Video duration exceeds 30 minutes (current: \(Int(duration/60)) minutes)"
        case .fileSizeExceeded(let size):
            return "File size exceeds 200MB (current: \(Int(size/1024/1024))MB)"
        case .invalidFormat:
            return "Only MP4 format videos are supported"
        case .pickerLoadFailed:
            return "Failed to load video from picker"
        }
    }
} 