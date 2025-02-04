Below is a comprehensive implementation plan that outlines all the necessary steps, file changes, and new files you’ll need to add in order to allow a user (from the profile tab) to tap one of their posts and then get options to edit or delete it.

---

## 1. Overview

When the currently authenticated user taps one of the posts (i.e. video posts) on their profile, you want to present a menu (such as a context menu or toolbar dropdown) that lets them choose between editing or deleting the video. If they choose edit, you’ll present an “Edit Video” view prefilled with the video’s current info (e.g. caption). If they choose delete, you’ll confirm with an alert and then remove the video from Firestore (and update the local cache/state).

---

## 2. Files to Update / Add

1. **New File:**

   - **Tiktok/Views/EditVideoView.swift**  
     – A new SwiftUI view permitting video editing.

2. **Updated Files:**
   - **Tiktok/Views/VideoDetailView.swift**  
     – Add a toolbar/menu button (visible only when the video was posted by the current user) that shows “Edit” and “Delete” options.
   - **Tiktok/Services/FirestoreService.swift**  
     – Add two new methods: one for updating a video and one for deleting a video document (including updating the user’s posts count).
   - **Tiktok/ViewModels/ProfileViewModel.swift**  
     – Add wrapper methods that call the new Firestore service functions and update the local cache (or list) accordingly.

---

## 3. Step-by-Step Implementation

### Step 1. Create EditVideoView.swift

Create a new SwiftUI view that presents a form for editing the video’s details (for example, editing the caption). This view should be presented as a sheet from the VideoDetailView.

Below is an example implementation:

```swift: Tiktok/Views/EditVideoView.swift
import SwiftUI

struct EditVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    let video: VideoModel
    let onSave: (VideoModel) async -> Bool

    init(video: VideoModel, onSave: @escaping (VideoModel) async -> Bool) {
        self.video = video
        self._caption = State(initialValue: video.caption)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Caption")) {
                    TextField("Enter caption", text: $caption)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Video")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            let updatedVideo = videoWithNewCaption
                            if await onSave(updatedVideo) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var videoWithNewCaption: VideoModel {
        var updated = video
        updated.caption = caption
        return updated
    }
}

struct EditVideoView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleVideo = VideoModel(
            id: "video123",
            userId: "user123",
            username: "tester",
            videoUrl: "https://example.com/video.mp4",
            caption: "My original caption",
            likes: 10,
            comments: [],
            timestamp: Date(),
            thumbnailUrl: nil
        )
        EditVideoView(video: sampleVideo) { updatedVideo in
            // preview save returns success immediately
            return true
        }
    }
}
```

### Step 2. Update FirestoreService.swift

Add two new methods to interact with Firestore for video updates and deletion.

```swift: Tiktok/Services/FirestoreService.swift
// Add these methods in the FirestoreService class

// Method to update video details (for editing)
func updateVideo(_ video: VideoModel) async throws {
    let videoRef = db.collection("videos").document(video.id)
    // For now, we update only the caption. You can extend this to add other fields.
    try await videoRef.updateData([
        "caption": video.caption
    ])
}

// Method to delete a video
func deleteVideo(video: VideoModel) async throws {
    let videoRef = db.collection("videos").document(video.id)
    try await videoRef.delete()

    // Also decrement the posts count for the user.
    let userRef = db.collection("users").document(video.userId)
    try await userRef.updateData([
        "postsCount": FieldValue.increment(Int64(-1))
    ])
}
```

### Step 3. Update ProfileViewModel.swift

In your profile view model, add wrapper functions that call these new FirestoreService methods and update the video cache.

```swift: Tiktok/ViewModels/ProfileViewModel.swift
extension ProfileViewModel {
    // Method to update a video (after editing)
    func updateVideo(_ video: VideoModel) async {
        do {
            try await firestoreService.updateVideo(video)
            videoCache[video.id] = video
        } catch {
            print("DEBUG: Error updating video: \(error.localizedDescription)")
            // Optionally, set an error state here
        }
    }

    // Method to delete a video
    func deleteVideo(_ video: VideoModel) async {
        do {
            try await firestoreService.deleteVideo(video: video)
            videoCache.removeValue(forKey: video.id)
        } catch {
            print("DEBUG: Error deleting video: \(error.localizedDescription)")
            // Optionally, set an error state here
        }
    }
}
```

### Step 4. Update VideoDetailView.swift

In the detail view (which is now presented when tapping on a post), add a toolbar menu (or context menu) that is shown only if the current user is the owner of the video. This menu will include “Edit” and “Delete” options.

Below is an example snippet of how you can modify VideoDetailView:

```swift: Tiktok/Views/VideoDetailView.swift
import SwiftUI
import FirebaseAuth

struct VideoDetailView: View {
    @Binding var video: VideoModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: ProfileViewModel
    @State private var showingEditSheet = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VideoContent(video: $video, isActive: true)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .font(.title2)
                }
            }
            // Options button – visible only if the current user owns this video
            if video.userId == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Edit") {
                            showingEditSheet = true
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Text("Delete")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditVideoView(video: video) { updatedVideo in
                await viewModel.updateVideo(updatedVideo)
                // Update the bound video to reflect changes
                video = updatedVideo
                return true
            }
        }
        .alert("Delete Video", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteVideo(video)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
    }
}
```

### Step 5. Testing and Final Adjustments

1. **Test in Simulator:**  
   – Run the app and navigate to the Profile tab.  
   – Tap one of your own posts to open the detail view.  
   – Verify that the “ellipsis” menu button appears.  
   – Test both the “Edit” (which should bring up the EditVideoView prepopulated with the current caption) and “Delete” actions (which should prompt a confirmation alert and delete the video on confirmation).

2. **Error Handling & UI Feedback:**  
   – Consider adding loading states or error messages in both the EditVideoView and within the ProfileViewModel if the update or deletion fails.

3. **Firestore Rules Verification:**  
   – Ensure your current Firestore rules for the “videos” collection already restrict update and deletion so that only the owner can modify or delete the video. (Your existing rules do this if you compare the video’s userId to the authenticated user’s id.)

4. **Code Cleanup & Refactor:**  
   – Remove any debug prints if no longer needed and verify that the local state remains consistent (for example, the video list in the grid view should update accordingly after a deletion).

---

## 4. Summary

- Create a new `EditVideoView.swift` to allow the user to modify the caption (and additional fields if needed).
- Add new methods in `FirestoreService.swift` to update and delete videos.
- Extend `ProfileViewModel.swift` to wrap these operations and update the local video cache.
- Update `VideoDetailView.swift` to add a toolbar button that presents a menu with edit and delete options, and tie the actions to the corresponding view model methods.
- Test the complete user flow for both editing and deleting videos on the profile tab.

Following these steps and file updates will integrate the edit/delete functionality seamlessly into your app.
