Below is an example of a comprehensive implementation plan. In our case we want to “wire up” bookmarking so that every video shows in real time whether it has been bookmarked (or unbookmarked) and so that the profile’s hamburger menu lets you open a sheet showing your bookmarked videos in the same grid format used for posts and liked posts. Follow these steps in order:

---

## 1. Update the Data Model

• **File:** Tiktok/Models/VideoModel.swift  
  – Add a new Boolean property (and helper methods) to track bookmark state. For example:

```swift:Models/VideoModel.swift
struct VideoModel: Identifiable, Codable, Hashable {
    // ... existing properties ...
    var isLiked: Bool = false
    // NEW: Track bookmark state
    var isBookmarked: Bool = false

    // Existing mutating methods...
    mutating func like() {
        likes += 1
        isLiked = true
    }

    mutating func unlike() {
        likes -= 1
        isLiked = false
    }

    // NEW: Mutating functions for bookmark toggling
    mutating func bookmark() {
        isBookmarked = true
    }

    mutating func unbookmark() {
        isBookmarked = false
    }

    // ... rest of the struct ...
}
```

---

## 2. Update Firestore Security Rules

• **File:** firebase/firestore.rules  
  – Add a new block for bookmarks. (This is modeled similarly to the user likes rules.) For example:

```firebase
// Add bookmarks rules after the likes rules
match /userBookmarks/{userId}/bookmarkedVideos/{videoId} {
  allow read: if true;
  allow create: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.userId == userId;
  allow delete: if request.auth != null && request.auth.uid == userId;
}
```

---

## 3. Extend FirestoreService with Bookmark Functions

• **File:** Tiktok/Services/FirestoreService.swift  
  – Add functions for bookmarking (and unbookmarking) a video, as well as a listener to observe a user’s bookmarked video IDs.

For example, add these new methods:

```swift
// Bookmark the video by writing to "userBookmarks" subcollection
func bookmarkVideo(videoId: String, userId: String) async throws {
    let data: [String: Any] = [
        "userId": userId,
        "videoId": videoId,
        "timestamp": FieldValue.serverTimestamp()
    ]
    try await db.collection("userBookmarks")
        .document(userId)
        .collection("bookmarkedVideos")
        .document(videoId)
        .setData(data)
}

// Unbookmark the video by deleting the document
func unbookmarkVideo(videoId: String, userId: String) async throws {
    try await db.collection("userBookmarks")
        .document(userId)
        .collection("bookmarkedVideos")
        .document(videoId)
        .delete()
}

// Add a realtime listener for the current user's bookmarks
func addUserBookmarksListener(userId: String, onChange: @escaping ([String]) -> Void) -> ListenerRegistration {
    return db.collection("userBookmarks")
        .document(userId)
        .collection("bookmarkedVideos")
        .addSnapshotListener { snapshot, error in
            guard let documents = snapshot?.documents else {
                print("DEBUG: Error fetching bookmarks: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            let videoIds = documents.map { $0.documentID }
            onChange(videoIds)
        }
}
```

---

## 4. Create a New Bookmark Service

• **File:** Tiktok/Services/BookmarkService.swift  
  – Encapsulate bookmark logic (including listening in real time and toggling bookmark state). By using its own service you keep bookmark logic separate from likes.

For example:

```swift:Services/BookmarkService.swift
import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
class BookmarkService: ObservableObject {
    static let shared = BookmarkService()
    private init() { }

    @Published var bookmarkedVideoIds: Set<String> = []
    private let firestoreService = FirestoreService.shared
    private var listener: ListenerRegistration?

    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        listener = firestoreService.addUserBookmarksListener(userId: userId) { [weak self] videoIds in
            self?.bookmarkedVideoIds = Set(videoIds)
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        bookmarkedVideoIds = []
    }

    func toggleBookmark(for video: inout VideoModel) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            if bookmarkedVideoIds.contains(video.id) {
                // Unbookmark video
                try await firestoreService.unbookmarkVideo(videoId: video.id, userId: userId)
                video.unbookmark()
            } else {
                // Bookmark video
                try await firestoreService.bookmarkVideo(videoId: video.id, userId: userId)
                video.bookmark()
            }
        } catch {
            print("DEBUG: Error toggling bookmark: \(error.localizedDescription)")
        }
    }
}
```

Remember to inject this service as an environment object (see step 8).

---

## 5. Update VideoContent View to Hook Up Bookmark Button

• **File:** Tiktok/Views/VideoContent.swift  
  – In the overlay of the video actions, replace the placeholder bookmark button with an actual button that uses the new BookmarkService. For example, change the bookmark button code from:

```swift
// Previous placeholder code:
Button {
    // TODO: Implement bookmarks
} label: {
    Image(systemName: "bookmark")
        .font(.title)
        .foregroundColor(.white)
}
```

to something like:

```swift
// Updated bookmark button
Button {
    Task {
        // Toggle bookmark state
        await bookmarkService.toggleBookmark(for: &video)
    }
} label: {
    Image(systemName: bookmarkService.bookmarkedVideoIds.contains(video.id) ? "bookmark.fill" : "bookmark")
        .font(.title)
        .foregroundColor(.white)
}
```

Make sure to add an environment object for the BookmarkService at the top of the file:

```swift
@EnvironmentObject private var bookmarkService: BookmarkService
```

---

## 6. Create a Bookmarks Grid View

The bookmarked videos should appear in a sheet using the grid format that we already use.

• **File:** Tiktok/Views/Bookmarks/BookmarksView.swift (create this new file)  
  – This view should leverage the existing VideoGridView. You can either create a new BookmarksViewModel or use BookmarkService and FirestoreService to fetch complete video details based on the IDs in bookmarkedVideoIds.

For example:

```swift
import SwiftUI

struct BookmarksView: View {
    @StateObject private var viewModel = BookmarksViewModel()

    var body: some View {
        NavigationStack {
            if viewModel.videos.isEmpty {
                Text("No bookmarks yet")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VideoGridView(videos: $viewModel.videos) { video in
                    // Handle video tap (navigate to VideoDetailView)
                    viewModel.selectedVideo = video
                }
                .navigationDestination(item: $viewModel.selectedVideo) { video in
                    VideoDetailView(video: Binding(
                        get: { video },
                        set: { newValue in
                            // Update video in the grid if necessary
                            if let index = viewModel.videos.firstIndex(where: { $0.id == newValue.id }) {
                                viewModel.videos[index] = newValue
                            }
                            viewModel.selectedVideo = newValue
                        }
                    ))
                }
            }
        }
        .task {
            await viewModel.fetchBookmarkedVideos()
        }
    }
}
```

And create the accompanying view model:

• **File:** Tiktok/ViewModels/BookmarksViewModel.swift

```swift
import SwiftUI

@MainActor
class BookmarksViewModel: ObservableObject {
    @Published var videos: [VideoModel] = []
    @Published var selectedVideo: VideoModel?

    private let firestoreService = FirestoreService.shared
    private var bookmarkService = BookmarkService.shared

    func fetchBookmarkedVideos() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        do {
            // Get the list of bookmarked video IDs from BookmarkService
            let bookmarkedIds = Array(bookmarkService.bookmarkedVideoIds)
            // Fetch details for each video (this could be optimized by a batched request)
            var fetchedVideos: [VideoModel] = []
            for videoId in bookmarkedIds {
                if let video = try? await firestoreService.fetchVideo(videoId: videoId) {
                    // Mark the video as bookmarked
                    var updatedVideo = video
                    updatedVideo.isBookmarked = true
                    fetchedVideos.append(updatedVideo)
                }
            }
            // Optionally sort videos (e.g. by timestamp)
            self.videos = fetchedVideos.sorted { $0.timestamp > $1.timestamp }
        } catch {
            print("DEBUG: Error fetching bookmarked videos: \(error.localizedDescription)")
        }
    }
}
```

---

## 7. Update Profile View’s Hamburger Menu

You need the menu to offer “Edit Profile”, then “Bookmarks”, then “Sign Out.”

• **File:** Tiktok/Views/Profile/ProfileView.swift  
  – In the toolbar menu (the hamburger button), add a new Button for bookmarks.  
  – Update or extend your sheet presentation logic (for example, by adding a new enum case such as `.bookmarks` to your sheet type) so that when your new bookmark option is tapped the BookmarksView sheet is presented.

For example, modify the menu in the toolbar:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
            Button {
                showEditProfile = true
            } label: {
                Label("Edit Profile", systemImage: "pencil")
            }
            // NEW: Bookmarks option in the middle
            Button {
                activeSheet = .bookmarks
            } label: {
                Label("Bookmarks", systemImage: "bookmark.fill")
            }
            Button(role: .destructive) {
                viewModel.signOut()
            } label: {
                Label("Sign Out", systemImage: "arrow.right.circle")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.black)
        }
    }
}
```

Then, update the sheet presentation to handle the new case:

```swift
.sheet(item: $activeSheet) { sheetType in
    switch sheetType {
    case .followers:
        UserListSheetView(sheetType: .followers, userId: userId)
    case .following:
        UserListSheetView(sheetType: .following, userId: userId)
    case .likes:
        UserListSheetView(sheetType: .likes, userId: userId)
    case .bookmarks:
        BookmarksView()
    }
}
```

Make sure your sheet type enum (likely defined in a common place such as in the Profile view file) now includes a new case “bookmarks” with an appropriate title.

---

## 8. Wire Up Environment Objects

• In your MainTabView (or an appropriate root view) add the BookmarkService as an environment object so that it can be used in VideoContent and BookmarksView. For example:

```swift
// In Tiktok/Views/MainTabView.swift
struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var appState = AppState.shared
    @StateObject private var bookmarkService = BookmarkService.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VideoFeedView()
                    .environment(\.tabSelection, $selectedTab)
                    .environmentObject(bookmarkService)
            }
            // ...other tabs remain unchanged...
            NavigationStack {
                ProfileView()
                    .environment(\.tabSelection, $selectedTab)
                    .environmentObject(bookmarkService)
            }
            // ...
        }
        .environmentObject(appState)
    }
}
```

Also, inside your BookmarkService, call `startListening()` (perhaps on initialization or in an onAppear in MainTabView) to begin tracking bookmark changes in real time.

---

## 9. Testing and Verification

• Test that:

- When you tap the bookmark button on a video, the icon toggles immediately (using an optimistic update) and the change is reflected in Firestore.
- When you load the profile and open the “Bookmarks” sheet from the hamburger menu, the grid correctly displays your bookmarked videos.
- The bookmarking state is updated in real time if a bookmark is added or removed from another device or session.
- Error cases (e.g. network issues) are logged and the UI stays consistent.

---

## Summary

By following these steps, you will:

1. Extend the video model with bookmark state.
2. Extend and secure Firestore with bookmark-specific rules.
3. Add bookmark methods into your FirestoreService.
4. Create a new BookmarkService to manage realtime bookmark state.
5. Wire up VideoContent to toggle and display bookmark state.
6. Create a new Bookmarks view (with its own view model) to display videos in a grid.
7. Add a “Bookmarks” option in the profile menu that presents the bookmarks sheet.
8. Pass the new service via the environment so that all views update in real time.

This completes the comprehensive implementation plan.
