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
    
    // Constants for hit target
    private let progressBarHeight: CGFloat = 4
    private let hitTargetHeight: CGFloat = 30  // Standard touch target size
    private let segmentMarkerHeight: CGFloat = 8
    private let progressBarDraggingHeight: CGFloat = 8  // Height when dragging
    
    private var currentProgress: Double {
        if duration <= 0 { return 0 }
        if isDragging { return dragProgress }
        return min(1, max(0, progress))
    }
    
    private var currentBarHeight: CGFloat {
        isDragging ? progressBarDraggingHeight : progressBarHeight
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Hit target area with progress bar
            ZStack(alignment: .bottom) {
                // Hit target
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                onDragChanged(progress)
                            }
                            .onEnded { _ in
                                onDragEnded()
                            }
                    )
                
                // Progress bar container
                ZStack(alignment: .leading) {
                    // Background track with segment breaks
                    HStack(spacing: 4) {
                        if let segments = segments {
                            ForEach(segments.indices, id: \.self) { index in
                                let segment = segments[index]
                                let segmentWidth = (segment.endTime - segment.startTime) / duration * geometry.size.width
                                
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: segmentWidth, height: currentBarHeight)
                                    .cornerRadius(currentBarHeight / 2)
                            }
                        } else {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: currentBarHeight)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(currentBarHeight / 2)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isDragging)
                    
                    // Progress fill
                    HStack(spacing: 4) {
                        if let segments = segments {
                            ForEach(segments.indices, id: \.self) { index in
                                let segment = segments[index]
                                let segmentWidth = (segment.endTime - segment.startTime) / duration * geometry.size.width
                                let segmentProgress = max(0, min(1, (currentProgress * duration - segment.startTime) / (segment.endTime - segment.startTime)))
                                let fillWidth = segmentWidth * segmentProgress
                                
                                Rectangle()
                                    .fill(segment.isFiller ? Color.gray : Color.blue)
                                    .frame(width: fillWidth, height: currentBarHeight)
                                    .cornerRadius(currentBarHeight / 2)
                            }
                        } else {
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: max(0, min(geometry.size.width, geometry.size.width * currentProgress)), height: currentBarHeight)
                                .cornerRadius(currentBarHeight / 2)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isDragging)
                }
            }
        }
        .frame(height: hitTargetHeight)
        .padding(.bottom, 2)
    }
}

struct VideoSegment {
    let startTime: Double
    let endTime: Double
    let topic: String
    let summary: String
} 