Below is a comprehensive, ordered implementation plan to add “comments” functionality on posts. This plan covers backend (Firestore rules and indexes), model updates, service methods, view/viewmodel changes, and testing.

---

## 1. Update Firestore Backend

### a. Firestore Security Rules

Since you’ve created a new “comments” collection, allow authenticated users to create comments and allow public read access while restricting update/delete to comment owners. Edit your file:

File: `firebase/firestore.rules`

```firebase
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Existing rules …

    // Comments collection rules
    match /comments/{commentId} {
      // Anyone can read comments
      allow read: if true;
      // Only authenticated users can create comments
      allow create: if request.auth != null &&
                      request.resource.data.keys().hasAll(['videoId', 'userId', 'text', 'timestamp']) &&
                      request.resource.data.userId == request.auth.uid;
      // Only comment owner can update or delete
      allow update, delete: if request.auth != null && request.auth.uid == resource.data.userId;
    }

    // Default deny all other collections
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

### b. Firestore Indexes

If you plan to query the comments by video and order them by timestamp, update your indexes:

File: `firebase/firestore.indexes.json`

```json
{
  "indexes": [
    {
      "collectionGroup": "videos",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "comments",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "videoId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

---

## 2. Update Models

### a. Create a Comment Model

Although you already have a nested `Comment` in `VideoModel.swift`, it’s best to create a dedicated model for comments since they are now stored in their own collection.

Create a new file:

File: `Tiktok/Models/CommentModel.swift`

```swift
import Foundation
import FirebaseFirestore

struct CommentModel: Identifiable, Codable {
    var id: String = UUID().uuidString
    let videoId: String
    let userId: String
    let text: String
    let timestamp: Date

    // Initializer from Firestore document
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let videoId = data["videoId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
            return nil
        }
        self.id = document.documentID
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
    }

    // Convert to Firestore dictionary
    func toDictionary() -> [String: Any] {
        return [
            "videoId": videoId,
            "userId": userId,
            "text": text,
            "timestamp": Timestamp(date: timestamp)
        ]
    }
}
```

---

## 3. Update Firestore Service

Extend your FirestoreService to handle comment operations.

File: `Tiktok/Services/FirestoreService.swift`  
_Add the following functions (you can place these near your video methods):_

```swift
// MARK: - Comment Methods

// Adds a new comment for a given video
func addComment(videoId: String, text: String) async throws {
    guard let currentUserId = Auth.auth().currentUser?.uid else {
        throw NSError(domain: "FirestoreService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
    }

    let commentData: [String: Any] = [
        "videoId": videoId,
        "userId": currentUserId,
        "text": text,
        "timestamp": FieldValue.serverTimestamp()
    ]

    // Save to the separate "comments" collection
    _ = try await db.collection("comments").addDocument(data: commentData)
}

// Fetch comments for a given videoId
func fetchComments(forVideoId videoId: String) async throws -> [CommentModel] {
    let snapshot = try await db.collection("comments")
        .whereField("videoId", isEqualTo: videoId)
        .order(by: "timestamp", descending: false)
        .getDocuments()

    let comments = snapshot.documents.compactMap { CommentModel(document: $0) }
    return comments
}
```

---

## 4. Create/Update ViewModels

### a. Create a Comments ViewModel

This view model will manage the comment list and new comment posting. Create a new file:

File: `Tiktok/ViewModels/CommentsViewModel.swift`

```swift
import Foundation

@MainActor
class CommentsViewModel: ObservableObject {
    @Published var comments: [CommentModel] = []
    @Published var errorMessage: String?
    @Published var isPosting = false

    private let firestoreService = FirestoreService.shared
    let videoId: String

    init(videoId: String) {
        self.videoId = videoId
        Task {
            await fetchComments()
        }
    }

    func fetchComments() async {
        do {
            let fetchedComments = try await firestoreService.fetchComments(forVideoId: videoId)
            comments = fetchedComments
        } catch {
            errorMessage = error.localizedDescription
            print("DEBUG: Unable to fetch comments: \(error.localizedDescription)")
        }
    }

    func postComment(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPosting = true
        do {
            try await firestoreService.addComment(videoId: videoId, text: text)
            await fetchComments() // Refresh comments list
        } catch {
            errorMessage = error.localizedDescription
            print("DEBUG: Failed to post comment: \(error.localizedDescription)")
        }
        isPosting = false
    }
}
```

---

## 5. Update Views (UI)

### a. Create a Comments View

This view displays the list of comments for a video and includes a text input to add a new comment.

Create a new file:

File: `Tiktok/Views/CommentsView.swift`

```swift
import SwiftUI

struct CommentsView: View {
    @StateObject var viewModel: CommentsViewModel
    @State private var newCommentText: String = ""

    var body: some View {
        VStack {
            // Comments List
            if viewModel.comments.isEmpty {
                Text("No comments yet.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List(viewModel.comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comment.text)
                            .font(.body)
                        Text(comment.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .listStyle(PlainListStyle())
            }
            Divider()
            // New Comment Input
            HStack {
                TextField("Add a comment...", text: $newCommentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: {
                    Task {
                        await viewModel.postComment(text: newCommentText)
                        newCommentText = ""
                    }
                }) {
                    if viewModel.isPosting {
                        ProgressView()
                    } else {
                        Text("Post")
                    }
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Comments")
        .onAppear {
            Task { await viewModel.fetchComments() }
        }
    }
}

struct CommentsView_Previews: PreviewProvider {
    static var previews: some View {
        CommentsView(viewModel: CommentsViewModel(videoId: "sampleVideoId"))
    }
}
```

### b. Update the Video/Post Feed View

Update the view where a comment button is present (e.g., in `Tiktok/Views/VideoFeedView.swift`) so that tapping the comment button shows the new CommentsView.

Locate the comment button code and modify it to push a navigation link. For example:

File: `Tiktok/Views/VideoFeedView.swift`

```swift
// Inside your video view cell
NavigationLink(destination: CommentsView(viewModel: CommentsViewModel(videoId: video.id))) {
    VStack(spacing: 4) {
        Image(systemName: "bubble.right")
            .font(.title)
        Text("\(video.comments.count)") // Optionally update with the count from the comments view model
            .font(.caption)
    }
    .foregroundColor(.white)
}
```

---

## 6. Testing and Verification

1. **Local Testing:**

   - Run the Firebase Emulator Suite (if set up) to test security rules locally:
     ```bash
     firebase emulators:start
     ```
   - Test creating a comment from the UI and verify that it appears in the CommentsView.
   - Confirm that unauthorized users cannot write to the comments collection (using the emulator).

2. **Integration Testing:**

   - Ensure that when a user posts a comment, the list refreshes correctly.
   - Verify that errors (e.g., due to network issues) are properly handled and displayed.

3. **Backend Verification:**
   - Check Firebase Console to ensure new comment documents are created with correct fields.
   - Validate that the Firestore indexes and rules are active.

---

## Summary of Affected/Added Files

- **Firebase Configuration:**

  - `firebase/firestore.rules` (add rules for the comments collection)
  - `firebase/firestore.indexes.json` (add an index for `comments`)

- **Models:**

  - New file: `Tiktok/Models/CommentModel.swift`

- **Services:**

  - Edit `Tiktok/Services/FirestoreService.swift` (add `addComment` and `fetchComments` functions)

- **ViewModels:**

  - New file: `Tiktok/ViewModels/CommentsViewModel.swift`

- **Views:**
  - New file: `Tiktok/Views/CommentsView.swift`
  - Edit `Tiktok/Views/VideoFeedView.swift` (update comment button to navigate to `CommentsView`)

---

Following this plan step by step will integrate a new, dedicated comments feature for posts in your app. Happy coding!
