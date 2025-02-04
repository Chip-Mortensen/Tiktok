Below is an implementation plan for adding real‑time upload progress to the video upload feature, using SwiftUI and Firebase Storage in the existing codebase.

---

## 1. Requirements & Goals

- **Objective:**  
  Show the upload progress in real time so that users know how much of their video has been uploaded. This can be done by displaying a progress indicator (e.g., a progress bar) updating as the upload proceeds.

- **Acceptance Criteria:**
  - The upload process displays a progress view (or progress bar) that updates from 0% to 100% as the upload proceeds.
  - The progress indicator uses the data from Firebase Storage’s upload task (e.g., via its progress observers).
  - When the upload completes (or errors), the UI properly resets or shows an error message.

---

## 2. High-Level Approach

- **Firebase Storage Upload Task:**  
  Instead of using an all‑at‑once async “putDataAsync” call, switch to an approach that leverages a Firebase StorageUploadTask and its ability to observe progress updates.

  - Use Firebase’s observer API (e.g., observe(.progress)) to capture progress events.
  - Wrap this in your async function (or use a callback) so that the higher‑level view model is informed of progress updates.

- **View Model Update:**  
  The existing VideoUploadViewModel already has an @Published property called “uploadProgress” (of type Double). Update this property in real time as progress events are received.

- **UI Changes:**  
  Modify the upload view to display a SwiftUI ProgressView (or custom progress indicator) that binds to the view model’s “uploadProgress” property and gives the user immediate feedback.

---

## 3. Detailed Tasks

### A. Update VideoUploadService

1. **Modify the Function Signature:**  
   Update the upload function signature to accept a progress callback. For instance:

   ```swift
   func uploadVideo(videoURL: URL, userId: String, caption: String, progressHandler: @escaping (Double) -> Void) async throws -> VideoModel {
       // …
   }
   ```

2. **Observe Upload Progress:**  
   Use Firebase Storage’s upload task observer to emit real‑time progress updates. For example:

   ```swift
   let uploadTask = videoRef.putData(videoData, metadata: videoMetadata) { metadata, error in
       // Completion callback: handle errors or complete the process
   }

   // Listen to progress events
   uploadTask.observe(.progress) { snapshot in
       if let progress = snapshot.progress {
           let fractionCompleted = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
           progressHandler(fractionCompleted)
       }
   }
   ```

   - Wrap or await the completion as needed, and then continue with downloading the final URLs and saving metadata to Firestore.

3. **Error Handling:**  
   Ensure that if the upload task errors out, the error is propagated and the progress_handler either stops updating or resets the progress.

### B. Update VideoUploadViewModel

1. **Pass in the Progress Handler:**  
   Inside your existing `uploadVideo(userId:)` function, update the call to use the new progress tracking mechanism:

   ```swift
   _ = try await videoUploadService.uploadVideo(
       videoURL: videoURL,
       userId: userId,
       caption: caption
   ) { progress in
       // Update progress on the main thread
       Task { @MainActor in
           self.uploadProgress = progress
       }
   }
   ```

2. **State Management:**
   - Ensure the view model resets “uploadProgress” to 0 on completion or error.
   - Keep “isUploading” updated to properly toggle the UI indicator.

### C. UI Changes in the Upload View

1. **Display the Progress Bar:**  
   In the view that allows the user to initiate a video upload (e.g., VideoUploadView), conditionally display a progress view when an upload is in progress:

   ```swift
   if viewModel.isUploading {
       ProgressView(value: viewModel.uploadProgress, total: 1.0)
           .padding()
       Text("\(Int(viewModel.uploadProgress * 100))% uploaded")
           .foregroundColor(.gray)
   }
   ```

   - This ensures users see a clear visual indication of progress.

2. **Styling & User Feedback:**
   - Consider additional UI feedback (e.g., disabling the upload button, showing a spinner in combination with the progress view, etc.).
   - Once the upload completes, hide the progress view or transition to a "success" state.

---

## 4. Testing & Verification

1. **Unit & Integration Testing:**

   - Write tests (or manually test) to confirm that the progressHandler is called with intermediate values between 0 and 1.
   - Verify that “uploadProgress” in the view model updates in real time.

2. **UI/UX Testing:**

   - Manually test in the simulator and on a device under various network conditions.
   - Ensure that the progress view renders properly and resets appropriately on success/failure.

3. **Handle Edge Cases:**
   - Test for canceled uploads and ensure that any in‑progress state is handled gracefully.

---

## 5. Documentation & Deployment

- **Update In‑Code Documentation:**

  - Add comments in VideoUploadService and VideoUploadViewModel describing the progress update mechanism.

- **Update User Documentation/Changelog:**

  - Note the new real‑time upload progress feature in release notes or update logs.

- **Deployment:**
  - After thorough testing, merge the changes and deploy them to a staging environment before production rollout.

---

By following these steps, the video upload process will report progress in real time, providing the user with immediate feedback during the upload process.
