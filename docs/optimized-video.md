Below is an example implementation plan outlining the overall design, backend changes, and frontend updates:

---

## 1. Update Your Data Model

• Add a new property (e.g. m3u8Url) to your VideoModel to store the generated HLS file URL.  
• Update Firestore rules (if needed) and any serializers/decoders so that the new field is read and written properly.

Example change to your VideoModel:

```swift:Models/VideoModel.swift
struct VideoModel: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    var username: String?
    let videoUrl: String
    var caption: String
    var likes: Int
    var comments: [Comment]
    var commentsCount: Int
    let timestamp: Date
    var thumbnailUrl: String?
    var m3u8Url: String? // New field for the HLS file
    var isLiked: Bool = false
}
```

---

## 2. Extend the Video Upload Workflow

### A. Upload as Usual

• Continue to upload the original mp4 file (and thumbnail) as you already do in your VideoUploadService.  
• Save the initial Firestore document with m3u8Url either null or omitted.

### B. Trigger Transcoding Asynchronously

After the mp4 upload completes:

• Trigger your transcoding process by:

- Calling a Cloud Function (or another backend service endpoint) with the details of the uploaded mp4.
- Passing the storage path or download URL so the transcoder can access it.

• This Cloud Function could be triggered by an HTTP callable request or even by a Storage event (whenever a new video file is created).

---

## 3. Integrate With a Transcoder API

### A. Set Up the Transcoder Service

• Choose your transcoder provider (for example, Google Cloud Transcoder or AWS Elastic Transcoder).  
• Set up a pipeline that converts the mp4 into HLS format (which creates an .m3u8 playlist and associated segment files).

### B. Asynchronous Processing

• The Cloud Function will call the transcoder API asynchronously, submitting the mp4 video URL and specifying an output bucket or location for the HLS files.  
• Monitor the transcoding job (you might use polling, pub/sub callbacks, or Cloud Function triggers on job completion).

### C. Update Firestore on Completion

• Once the transcoding process completes and the .m3u8 file is available:

- Get the download URL for the .m3u8 file (and ensure that the segments can also be accessed properly).
- Update the corresponding video document in Firestore by setting its m3u8Url property.

A pseudo-code outline for the Cloud Function might look like this:

```javascript:functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.onVideoUpload = functions.storage.object().onFinalize(async (object) => {
  // Check if the uploaded file is an mp4 under the expected path.
  if (object.contentType !== "video/mp4") return;

  // Trigger transcoder API job (pseudo-code)
  const videoUrl = object.mediaLink;
  const transcoderJob = await startTranscoderJob(videoUrl);

  // Wait for transcoding job completion (or listen via Pub/Sub trigger)
  const m3u8DownloadUrl = await waitForJobCompletion(transcoderJob);

  // Update Firestore video document with the m3u8Url
  const videoDocId = extractVideoIdFromPath(object.name);
  await admin.firestore().collection("videos").doc(videoDocId).update({
    m3u8Url: m3u8DownloadUrl
  });
});
```

_Note: In production your transcoding job management might be more complex. This serves as a high-level outline._

---

## 4. Modify Video Playback on the Client

### A. Use the m3u8Url if Available

• In your video playback code (e.g. in VideoContent and CustomVideoPlayer):

- Check if the video object has an m3u8Url.
- If yes, initialize the AVPlayer with the .m3u8 URL.
- If not (or if transcoding is still pending), fall back to the original mp4 URL.

Example of choosing the playback source:

```swift:Views/VideoContent.swift
if let m3u8UrlString = video.m3u8Url, let m3u8Url = URL(string: m3u8UrlString) {
    // Use the HLS (m3u8) source for playback.
    let playerItem = AVPlayerItem(url: m3u8Url)
    player = AVPlayer(playerItem: playerItem)
} else if let videoUrl = URL(string: video.videoUrl) {
    // Fallback to the original mp4.
    let playerItem = AVPlayerItem(url: videoUrl)
    player = AVPlayer(playerItem: playerItem)
}
```

### B. UI Considerations

• Optionally indicate in the UI if transcoding is still in progress.  
• Once the Firestore document is updated with m3u8Url, the next time the video is played the new URL will be used.

---

## 5. Testing & Deployment

### A. Test the Upload Process

• Upload several videos and check that:

- The mp4 and thumbnail are saved.
- The Cloud Function (or your backend service) is triggered.
- The transcoder job completes and updates the m3u8Url in the video document.

### B. Validate Streaming Playback

• Verify with different network conditions that HLS playback works smoothly.  
• Ensure that if the .m3u8 file isn’t yet available, the fallback to mp4 works without disrupting the user experience.

### C. Monitor and Debug

• Set up logging and dashboards so you can monitor transcoding job status and any errors (both in your Cloud Function and in the transcoder service).  
• Provide tests to simulate failures and ensure your fallback logic works properly.

---

## 6. Summary

• Add a new m3u8Url field to your video model and Firestore documents.  
• Trigger a post-upload transcoding process using a Cloud Function (or similar service) to convert mp4 videos into HLS format.  
• When transcoding completes, update the Firestore document with the .m3u8 download URL.  
• In the video player on the client, check for the presence of m3u8Url and default to it; fall back to the original mp4 URL if necessary.

This plan gives you a clear roadmap to add HLS playback with a fallback mechanism while keeping your upload and transcoding workflows decoupled and asynchronous.
