import SwiftUI
import AVKit

struct VideoProgressBar: View {
    let progress: Double
    let duration: Double
    let isDragging: Bool
    let dragProgress: Double
    let onDragChanged: (Double) -> Void
    let onDragEnded: () -> Void
    let segments: [VideoModel.Segment]?
    
    private let progressBarHeight: CGFloat = 4
    private let hitTargetHeight: CGFloat = 30
    private let progressBarDraggingHeight: CGFloat = 8
    
    // MARK: - Computed Properties
    private var currentProgress: Double {
        if duration <= 0 { return 0 }
        if isDragging { return dragProgress }
        return min(1, max(0, progress))
    }
    
    private var currentBarHeight: CGFloat {
        isDragging ? progressBarDraggingHeight : progressBarHeight
    }
    
    // MARK: - View Body
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            
            ZStack(alignment: .leading) {
                // Background track with integrated progress
                if let segments = segments {
                    HStack(spacing: 0) {
                        ForEach(segments.indices, id: \.self) { index in
                            let segment = segments[index]
                            let isFirst = index == 0
                            let isLast = index == segments.count - 1
                            let segmentWidth = calculateSegmentWidth(segment: segment, totalWidth: width)
                            
                            ZStack(alignment: .leading) {
                                // Background
                                Rectangle()
                                    .fill(segment.isFiller ? Color.yellow.opacity(0.4) : Color.white.opacity(0.3))
                                
                                // Progress fill
                                if let fillWidth = calculateSegmentFillWidth(segment: segment, totalWidth: width) {
                                    Rectangle()
                                        .fill(segment.isFiller ? Color.yellow : Color.blue)
                                        .frame(width: fillWidth)
                                }
                            }
                            .frame(width: segmentWidth, height: currentBarHeight)
                            .cornerRadius(currentBarHeight / 2)
                            .mask(
                                HStack(spacing: 0) {
                                    if isFirst {
                                        Rectangle()
                                            .frame(width: currentBarHeight)
                                        Rectangle()
                                            .frame(maxWidth: .infinity)
                                    } else if isLast {
                                        Rectangle()
                                            .frame(maxWidth: .infinity)
                                        Rectangle()
                                            .frame(width: currentBarHeight)
                                    } else {
                                        Rectangle()
                                    }
                                }
                            )
                        }
                    }
                } else {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: currentBarHeight)
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: width * currentProgress, height: currentBarHeight)
                    }
                    .cornerRadius(currentBarHeight / 2)
                }
            }
            .frame(height: currentBarHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let rawProgress = value.location.x / width
                        let boundedProgress = min(1, max(0, rawProgress))
                        onDragChanged(boundedProgress)
                    }
                    .onEnded { _ in
                        handleDragEnd()
                    }
            )
        }
        .frame(height: hitTargetHeight)
    }
    
    // MARK: - Helper Functions
    private func calculateSegmentWidth(segment: VideoModel.Segment, totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let segmentDuration = max(0, segment.endTime - segment.startTime)
        let segmentWidth = CGFloat(segmentDuration / duration) * totalWidth
        return max(0, segmentWidth)  // Ensure non-negative width
    }
    
    private func calculateSegmentFillWidth(segment: VideoModel.Segment, totalWidth: CGFloat) -> CGFloat? {
        guard duration > 0 else { return nil }
        let progressTime = currentProgress * duration
        
        // If progress hasn't reached this segment
        if progressTime <= segment.startTime {
            return nil
        }
        
        // If progress is within this segment
        if progressTime < segment.endTime {
            let segmentProgress = (progressTime - segment.startTime) / (segment.endTime - segment.startTime)
            return calculateSegmentWidth(segment: segment, totalWidth: totalWidth) * CGFloat(segmentProgress)
        }
        
        // If progress has passed this segment
        return calculateSegmentWidth(segment: segment, totalWidth: totalWidth)
    }
    
    private func handleDragEnd() {
        onDragEnded()
    }
}

struct VideoSegment {
    let startTime: Double
    let endTime: Double
    let topic: String
    let summary: String
} 