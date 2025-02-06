import SwiftUI
import AVKit

struct VideoProgressBar: View {
    let progress: Double
    let duration: Double
    let isDragging: Bool
    let dragProgress: Double
    let onDragChanged: (Double) -> Void
    let onDragEnded: () -> Void
    let segments: [VideoSegment]?
    
    private var currentProgress: Double {
        // Ensure progress is between 0 and 1
        if duration <= 0 { return 0 }
        if isDragging { return dragProgress }
        return min(1, max(0, progress))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                
                // Progress fill
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * currentProgress)), height: 4)
                
                // Segment markers
                if let segments = segments {
                    ForEach(segments, id: \.startTime) { segment in
                        let position = geometry.size.width * (segment.startTime / duration)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3, height: 8)
                            .position(x: position, y: 4)
                            .overlay {
                                // Show labels on hover
                                HoverLabel(labels: segment.labels)
                                    .offset(y: -20)
                            }
                    }
                }
                
                // Draggable handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .position(x: geometry.size.width * currentProgress, y: 4)
                    .opacity(isDragging ? 1 : 0)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dragProgress = max(0, min(1, value.location.x / geometry.size.width))
                        onDragChanged(dragProgress)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
        }
        .frame(height: 12) // Increased height to accommodate segment markers and handle
    }
}

struct HoverLabel: View {
    let labels: [String]
    @State private var isHovering = false
    
    var body: some View {
        Text(labels.joined(separator: ", "))
            .font(.caption2)
            .padding(4)
            .background(.ultraThinMaterial)
            .cornerRadius(4)
            .opacity(isHovering ? 1 : 0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
    }
}

#Preview {
    VideoProgressBar(
        progress: 0.5,
        duration: 60.0,
        isDragging: false,
        dragProgress: 0.0,
        onDragChanged: { _ in },
        onDragEnded: {},
        segments: [
            VideoSegment(startTime: 10.0, endTime: 15.0, labels: ["Dance"], confidence: 0.9),
            VideoSegment(startTime: 30.0, endTime: 35.0, labels: ["Music", "Performance"], confidence: 0.85)
        ]
    )
    .frame(height: 20)
    .padding()
    .background(Color.black)
} 