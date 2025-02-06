import SwiftUI

struct VideoSegmentOverlay: View {
    let segments: [VideoModel.Segment]?
    let currentProgress: Double
    let duration: Double
    let isDragging: Bool
    
    private var activeSegment: VideoModel.Segment? {
        guard let segments = segments,
              duration > 0 else { return nil }
        
        let currentTime = currentProgress * duration
        return segments.first { segment in
            currentTime >= segment.startTime && 
            currentTime <= segment.endTime
        }
    }
    
    var body: some View {
        if isDragging, let segment = activeSegment {
            VStack(alignment: .leading, spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.8), .black.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(segment.topic)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(segment.summary)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .transition(.opacity)
        }
    }
} 