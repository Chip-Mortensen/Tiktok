import SwiftUI
import AVKit

struct SmartSkipControls: View {
    let player: AVPlayer
    let segments: [VideoModel.Segment]?
    let currentProgress: Double
    let duration: Double
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var smartSkipManager: SmartSkipManager
    
    private var currentFillerSegment: VideoModel.Segment? {
        guard let segments = segments,
              duration > 0 else { return nil }
        
        let currentTime = currentProgress * duration
        return segments.first { segment in
            segment.isFiller && 
            currentTime >= segment.startTime && 
            currentTime <= segment.endTime
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Smart Skip Toggle
                Toggle("Auto-Skip Filler Content", isOn: $smartSkipManager.isAutoSkipEnabled)
                    .tint(.blue)
                    .padding(.horizontal)
                
                // Skip Controls - only show if auto-skip is disabled
                if !smartSkipManager.isAutoSkipEnabled, let currentFiller = currentFillerSegment {
                    VStack(spacing: 20) {
                        Button {
                            let targetTime = CMTime(seconds: currentFiller.endTime, preferredTimescale: 1000)
                            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                            dismiss()
                        } label: {
                            Label("Skip Filler", systemImage: "forward.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Segments List
                if let segments = segments {
                    List {
                        ForEach(segments.indices, id: \.self) { index in
                            let segment = segments[index]
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(segment.topic)
                                        .font(.headline)
                                    Text(segment.summary)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if segment.isFiller {
                                    Image(systemName: "scissors")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let targetTime = CMTime(seconds: segment.startTime, preferredTimescale: 1000)
                                player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                                dismiss()
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Smart Skip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
} 