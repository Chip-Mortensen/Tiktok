import Foundation

class SmartSkipManager: ObservableObject {
    @Published var isAutoSkipEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSkipEnabled, forKey: "isAutoSkipEnabled")
        }
    }
    private var lastSkippedSegmentId: String?
    
    init() {
        self.isAutoSkipEnabled = UserDefaults.standard.bool(forKey: "isAutoSkipEnabled")
    }
    
    func shouldSkipSegment(_ segment: VideoModel.Segment) -> Bool {
        guard isAutoSkipEnabled,
              segment.isFiller,
              lastSkippedSegmentId != "\(segment.startTime)-\(segment.endTime)" else {
            return false
        }
        lastSkippedSegmentId = "\(segment.startTime)-\(segment.endTime)"
        return true
    }
    
    func resetSkipTracking() {
        lastSkippedSegmentId = nil
    }
} 