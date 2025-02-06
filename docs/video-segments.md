# Comprehensive Implementation Plan for Video Segments

## 1. Update VideoModel

```swift
struct VideoSegment: Codable, Hashable {
    let startTime: Double
    let endTime: Double
    let labels: [String]
    let confidence: Double
}

// Add to VideoModel
struct VideoModel {
    // ... existing fields ...
    var segments: [VideoSegment]?
    var analysisStatus: VideoAnalysisStatus

    enum VideoAnalysisStatus: String, Codable {
        case pending
        case inProgress
        case completed
        case failed
    }
}
```

## 2. Create Cloud Function

Create a new function `analyzeVideo.ts` alongside your existing HLS conversion:

```typescript
export const analyzeVideo = onObjectFinalized(async (event) => {
  const object = event.data;
  const filePath = object.name;

  // Only process original MP4 uploads
  if (!filePath.startsWith('videos/') || !filePath.endsWith('.mp4')) {
    return;
  }

  const videoId = filePath.split('/').pop().replace('.mp4', '');
  const db = admin.firestore();

  try {
    // Update status to in-progress
    await db.collection('videos').doc(videoId).update({
      analysisStatus: 'inProgress',
    });

    // Initialize Video Intelligence API
    const client = new videoIntelligence.VideoIntelligenceServiceClient();
    const gcsUri = `gs://${object.bucket}/${filePath}`;

    const [operation] = await client.annotateVideo({
      inputUri: gcsUri,
      features: ['SHOT_CHANGE_DETECTION', 'LABEL_DETECTION'],
    });

    const [result] = await operation.promise();
    const segments = processVideoResults(result);

    // Update Firestore with results
    await db.collection('videos').doc(videoId).update({
      segments: segments,
      analysisStatus: 'completed',
    });
  } catch (error) {
    console.error('Video analysis failed:', error);
    await db.collection('videos').doc(videoId).update({
      analysisStatus: 'failed',
      analysisError: error.message,
    });
  }
});
```

## 3. Update FirestoreService

Add segment handling to the video upload and fetch methods:

```109:138:Tiktok/Services/FirestoreService.swift
    func uploadVideo(_ video: VideoModel) async throws {
        print("DEBUG: Starting Firestore video upload for video ID: \(video.id)")
        let videoData: [String: Any] = [
            "userId": video.userId,
            "videoUrl": video.videoUrl,
            "caption": video.caption,
            "likes": video.likes,
            "comments": video.comments.map { comment in
                return [
                    "id": comment.id,
                    "userId": comment.userId,
                    "text": comment.text,
                    "timestamp": comment.timestamp
                ]
            },
            "timestamp": FieldValue.serverTimestamp(),
            "thumbnailUrl": video.thumbnailUrl as Any,
            "m3u8Url": video.m3u8Url as Any
        ]

        // Update the videos collection using the video.id as the document ID
        try await db.collection("videos").document(video.id).setData(videoData)
        print("DEBUG: Video metadata saved to videos collection with ID: \(video.id)")

        // Update user's video count
        try await db.collection("users").document(video.userId).updateData([
            "postsCount": FieldValue.increment(Int64(1))
        ])
        print("DEBUG: User's video count updated for user: \(video.userId)")
    }
```

Modify to include segments:

```swift
let videoData: [String: Any] = [
    // ... existing fields ...
    "segments": [],
    "analysisStatus": "pending"
]
```

## 4. Update VideoProgressBar

Modify your existing progress bar to handle segments:

```1:35:Tiktok/Views/Components/VideoProgressBar.swift
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
```

Add segment markers:

```swift
struct VideoProgressBar: View {
    // ... existing properties ...
    let segments: [VideoSegment]?

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

                // Segment markers
                if let segments = segments {
                    ForEach(segments, id: \.startTime) { segment in
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 6)
                            .position(x: geometry.size.width * (segment.startTime / duration))
                            .overlay {
                                // Show labels on hover
                                HoverLabel(labels: segment.labels)
                            }
                    }
                }
            }
        }
        .frame(height: 6) // Increased for segment markers
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
```

## 5. Implementation Order

1. Update Models

   - Add VideoSegment and analysis status to VideoModel
   - Update all relevant decoders/encoders

2. Deploy Cloud Function

   - Set up Google Cloud Video Intelligence API
   - Deploy analyzeVideo function alongside HLS conversion
   - Test with sample video uploads

3. Update Services

   - Modify FirestoreService to handle segments
   - Update video fetching to include segment data
   - Add analysis status tracking

4. Update UI Components

   - Modify VideoProgressBar to show segments
   - Add hover interactions for segment labels
   - Show analysis status in upload flow

5. Testing
   - Test complete flow with various video types
   - Verify segment accuracy
   - Test error handling
   - Verify UI responsiveness

The analysis will happen asynchronously like your HLS conversion, so users won't have to wait for it to complete. The UI can update once the analysis is done, showing the segment markers in the progress bar.

Would you like me to detail any specific part of this implementation?
