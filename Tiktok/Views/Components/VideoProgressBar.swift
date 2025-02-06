import SwiftUI
import AVKit

struct VideoProgressBar: View {
    let progress: Double
    let duration: Double
    let isDragging: Bool
    let dragProgress: Double
    let onDragChanged: (Double) -> Void
    let onDragEnded: () -> Void
    
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
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 3)
                
                // Progress fill
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * currentProgress)), height: 3)
            }
        }
        .frame(height: 3)
    }
} 