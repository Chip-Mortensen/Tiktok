I'll help you create an implementation plan for adding a video progress indicator with scrubbing functionality. Based on the provided codebase, here's a comprehensive plan:

## Implementation Plan: Video Progress Indicator with Scrubbing

### 1. Create a Progress Indicator Component

First, create a new component called `VideoProgressBar.swift`:

```swift
struct VideoProgressBar: View {
    let progress: Double
    let duration: Double
    let isDragging: Bool
    let dragProgress: Double
    let onDragChanged: (Double) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 3)

                // Progress fill
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * (isDragging ? dragProgress : progress), height: 3)
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
        .frame(height: 3)
    }
}
```

### 2. Update VideoContent View

The VideoContent view needs to be modified to track video progress and handle scrubbing. Here's what needs to be changed in the existing VideoContent view:

Reference to existing VideoContent:

```175:351:Tiktok/Views/VideoFeedView.swift
struct VideoContent: View {
    @Binding var video: VideoModel
    let isActive: Bool
    @Binding var selectedUserId: String?
    @Binding var pushUserProfile: Bool
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    @EnvironmentObject private var videoService: VideoService
    @EnvironmentObject private var bookmarkService: BookmarkService
    @State private var showingComments = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabSelection) private var tabSelection

    var body: some View {
        ZStack {
            Color.black

            if let player = player {
                CustomVideoPlayer(player: player)
                    .gesture(
                        TapGesture()
                            .onEnded { _ in
                                // Only handle mute toggle if not interacting with other UI elements
                                if !pushUserProfile {
                                    appState.isMuted.toggle()
                                }
                            }
                    )
            } else if let thumbnailUrl = video.thumbnailUrl,
                      let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } placeholder: {
                    Color.black
                }
            }

            // Action buttons overlay
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    // Video info (left side)
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            print("DEBUG: Username tapped for: \(video.username ?? "unknown")")
                            player?.pause()
                            isPlaying = false

                            if video.userId == Auth.auth().currentUser?.uid {
                                // It's the current user: switch tab
                                dismiss()
                                tabSelection.wrappedValue = 3  // Profile tab
                            } else {
                                // For another user, set the state to push the profile view
                                selectedUserId = video.userId
                                pushUserProfile = true
                            }
                        } label: {
                            Text("@\(video.username ?? "user")")
                                .font(.headline)

                        }
                        .buttonStyle(PlainButtonStyle())

                        Text(video.caption)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 60)

                    // Action buttons (right side)
                    VStack(spacing: 20) {
                        // Like Button
                        Button {
                            Task {
                                await videoService.toggleLike(for: video.id)
                                if let updatedVideo = videoService.videos[video.id] {
                                    video = updatedVideo
                                }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: video.isLiked ? "heart.fill" : "heart")
                                    .font(.title)
                                    .foregroundColor(video.isLiked ? .red : .white)
                                    .scaleEffect(video.isLiked ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: video.isLiked)
                                Text("\(video.likes)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }

                        // Comment Button
                        Button {
                            showingComments = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.right")
                                    .font(.title)
                                    .foregroundColor(.white)
                                CommentsCountBadgeV
                            }
                        }

                        // Bookmark Button
                        Button {
                            Task {
                                // Create a local copy
                                var videoToUpdate = video
                                await bookmarkService.toggleBookmark(for: &videoToUpdate)
                                // Update the binding after the async operation
                                video = videoToUpdate
                            }
                        } label: {
                            Image(systemName: bookmarkService.bookmarkedVideoIds.contains(video.id) ? "bookmark.fill" : "bookmark")
                                .font(.title)
                                .foregroundColor(.white)
                                .scaleEffect(video.isBookmarked ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: video.isBookmarked)
                        }

                        // Sound indicator
                        Image(systemName: appState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(viewModel: CommentsViewModel(videoId: video.id))
        }
        .onAppear {
            if isActive {
                setupAndPlay()
                videoService.setupVideoListener(videoId: video.id)
                videoService.videos[video.id] = video
            }
        }
        .onChange(of: isActive) { wasActive, isNowActive in
            if isNowActive {
                setupAndPlay()
                videoService.setupVideoListener(videoId: video.id)
            } else {
                player?.pause()
                isPlaying = false
                videoService.removeListener(videoId: video.id)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            isPlaying = false
            videoService.removeListener(videoId: video.id)
        }
        .onChange(of: appState.isMuted) { _, isMuted in
            player?.isMuted = isMuted
        }
        // Add observer for video updates
        .onChange(of: videoService.videos[video.id]) { _, updatedVideo in
            if let updatedVideo = updatedVideo {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    video = updatedVideo
                }
            }
        }
    }
```

Add these new state variables to VideoContent:

```swift
@State private var progress: Double = 0
@State private var duration: Double = 0
@State private var isDragging: Bool = false
@State private var dragProgress: Double = 0
@State private var timeObserver: Any?
```

### 3. Add Progress Tracking Logic

Add this method to VideoContent:

```swift
private func setupProgressTracking() {
    guard let player = player else { return }

    // Get video duration
    if let duration = player.currentItem?.duration {
        self.duration = CMTimeGetSeconds(duration)
    }

    // Remove existing observer if any
    if let existing = timeObserver {
        player.removeTimeObserver(existing)
    }

    // Create new time observer
    let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
        guard let self = self, !self.isDragging else { return }
        let currentTime = CMTimeGetSeconds(time)
        self.progress = currentTime / self.duration
    }
}
```

### 4. Add Progress Bar to Video Overlay

In the VideoContent body, add the progress bar above the action buttons:

```swift
// Add this just before the action buttons overlay
VideoProgressBar(
    progress: progress,
    duration: duration,
    isDragging: isDragging,
    dragProgress: dragProgress,
    onDragChanged: { newProgress in
        isDragging = true
        dragProgress = newProgress
        let time = CMTime(seconds: duration * newProgress, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    },
    onDragEnded: {
        isDragging = false
        if isActive {
            player?.play()
        }
    }
)
.padding(.bottom, 8)
```

### 5. Update Lifecycle Methods

Modify the setupAndPlay() method in VideoContent to include progress tracking:

```swift
private func setupAndPlay() {
    // Existing setup code...

    if player == nil {
        // Existing player setup code...

        // Add after player setup
        setupProgressTracking()
    }
    player?.play()
    isPlaying = true
}
```

Add cleanup in onDisappear:

```swift
.onDisappear {
    if let timeObserver = timeObserver {
        player?.removeTimeObserver(timeObserver)
    }
    player?.pause()
    player = nil
    isPlaying = false
    videoService.removeListener(videoId: video.id)
}
```

### 6. Handle State Changes

Update the video state handling when scrubbing:

```swift
private func handleScrubbing(to progress: Double) {
    guard let player = player else { return }

    // Pause while scrubbing
    if !isDragging {
        player.pause()
    }

    let time = CMTime(seconds: duration * progress, preferredTimescale: 600)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
}
```

## Implementation Notes:

1. The progress bar will be a thin white line at the bottom of each video
2. The filled portion represents current playback progress
3. When dragging, the video will pause and seek to the dragged position
4. When drag ends, playback resumes if the video was active
5. Progress updates every 0.1 seconds for smooth animation
6. The progress bar becomes slightly larger when being dragged for better user interaction
7. Progress tracking automatically cleans up when the video is no longer visible

## Testing Checklist:

1. Progress bar updates smoothly during normal playback
2. Dragging the progress bar seeks the video correctly
3. Progress bar updates properly when video loops
4. Cleanup happens correctly when switching between videos
5. Progress bar remains responsive even during long video playback
6. Seeking works accurately even on longer videos
7. Progress bar updates correctly after seeking

This implementation provides a smooth, native-feeling video progress indicator with scrubbing functionality similar to what you'd find in TikTok or Instagram Reels.
