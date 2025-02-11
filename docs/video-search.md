Below is one possible implementation plan to add video search into the app. The idea is to augment the existing search page so that it defaults to showing users but lets the user switch via a dropdown menu to search for videos. For video searches, you’ll query (for now) against a text field (e.g. transcription) and display matching videos in a grid layout (reusing the profile grid style).

Below are the step‐by‐step changes and new files you’ll need:

---

### 1. Define a Search Type Enum

Create a simple enum (in a new file or within your search view file) to differentiate between user and video searches.

```swift
// File: Tiktok/Models/SearchType.swift
enum SearchType: String, CaseIterable {
    case users = "Users"
    case videos = "Videos"
}
```

---

### 2. Update the Search Page UI

You’ll need to update your current search page (e.g. UsersSearchView) so that it:

- Defaults to “Users.”
- Displays a dropdown (or Menu) button in the navigation bar (or near the search bar) that lets the user switch between “Users” and “Videos.”

For example, update your view to add a state for the selected search type:

```swift
// File: Tiktok/Views/UsersSearchView.swift (may be renamed to SearchView.swift later)
import SwiftUI
import FirebaseAuth

struct SearchView: View {
    @StateObject private var usersViewModel = UsersSearchViewModel()
    @StateObject private var videoViewModel = VideoSearchViewModel()
    @State private var searchType: SearchType = .users
    @Environment(\.tabSelection) var tabSelection
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    SearchBarView(
                        searchQuery: Binding(
                            get: { searchType == .users ? usersViewModel.searchQuery : videoViewModel.searchQuery },
                            set: { newValue in
                                if searchType == .users {
                                    usersViewModel.searchQuery = newValue
                                } else {
                                    videoViewModel.searchQuery = newValue
                                }
                            }
                        ),
                        onClear: {
                            if searchType == .users {
                                usersViewModel.searchQuery = ""
                                usersViewModel.performSearch()
                            } else {
                                videoViewModel.searchQuery = ""
                                videoViewModel.performSearch()
                            }
                        },
                        onChange: {
                            if searchType == .users {
                                usersViewModel.performSearch()
                            } else {
                                videoViewModel.performSearch()
                            }
                        },
                        focusBinding: $isSearchFieldFocused
                    )

                    // Dropdown to toggle between user and video search
                    Menu {
                        ForEach(SearchType.allCases, id: \.self) { type in
                            Button(type.rawValue) {
                                searchType = type
                                // Optionally trigger search for the new type if needed.
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.title2)
                    }
                    .padding(.trailing)
                }

                // Conditional result view based on search type
                if searchType == .users {
                    UsersSearchResultsView(
                        isLoading: usersViewModel.isLoading,
                        searchQuery: usersViewModel.searchQuery,
                        searchResults: usersViewModel.searchResults,
                        tabSelection: tabSelection
                    )
                } else {
                    VideoSearchResultsView(
                        isLoading: videoViewModel.isLoading,
                        searchQuery: videoViewModel.searchQuery,
                        searchResults: videoViewModel.searchResults
                    )
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // Automatically focus the search field when in the search tab
            if tabSelection.wrappedValue == 1 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                isSearchFieldFocused = true
            }
        }
        .onChange(of: tabSelection.wrappedValue) { _, newValue in
            if newValue == 1 {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    isSearchFieldFocused = true
                }
            } else {
                isSearchFieldFocused = false
            }
        }
    }
}
```

> **Notes:**
>
> - The code above uses two view models (one for user search and one for video search) which we set up in separate steps.
> - The `SearchBarView` is reused from your current implementation.

---

### 3. Create a Video Search View Model

Add a new view model that will handle searching videos. For now, the search will simply look for a text match in the video’s transcription (or another fallback field like caption).

```swift
// File: Tiktok/ViewModels/VideoSearchViewModel.swift
import SwiftUI
import FirebaseFirestore

@MainActor
class VideoSearchViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [VideoModel] = []
    @Published var isLoading = false
    private let db = Firestore.firestore()
    private var searchTask: Task<Void, Never>?

    func performSearch() {
        // Cancel any previous task
        searchTask?.cancel()

        // Check that the query is not empty
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            self.searchResults = []
            self.isLoading = false
            return
        }

        isLoading = true

        searchTask = Task {
            // Debounce typing
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            do {
                // For now, we search for videos whose "transcription" field matches a prefix of the search string.
                // Note: Later we can rework to use a full-text search solution.
                let snapshot = try await db.collection("videos")
                    .whereField("transcription", isGreaterThanOrEqualTo: trimmedQuery)
                    .whereField("transcription", isLessThan: trimmedQuery + "\u{f8ff}")
                    .limit(to: 20)
                    .getDocuments()

                // Parse video documents into VideoModel
                var videos: [VideoModel] = []
                for document in snapshot.documents {
                    let data = document.data()
                    // Create a video model; assume transcription is included in the data (or fallback to caption)
                    let video = VideoModel(
                        id: document.documentID,
                        userId: data["userId"] as? String ?? "",
                        username: data["username"] as? String,
                        videoUrl: data["videoUrl"] as? String ?? "",
                        caption: data["caption"] as? String ?? "",
                        likes: data["likes"] as? Int ?? 0,
                        comments: [], // Parse comments if needed
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        thumbnailUrl: data["thumbnailUrl"] as? String,
                        m3u8Url: data["m3u8Url"] as? String,
                        commentsCount: data["commentsCount"] as? Int ?? 0,
                        segments: nil,
                        isLiked: false,
                        isBookmarked: false
                    )
                    videos.append(video)
                }

                // Update UI on main thread
                await MainActor.run {
                    self.searchResults = videos
                    self.isLoading = false
                }
            } catch {
                print("Video search error: \(error.localizedDescription)")
                await MainActor.run {
                    self.searchResults = []
                    self.isLoading = false
                }
            }
        }
    }
}
```

> **Important:**  
> In a real-world scenario you might want to add a dedicated transcription field to your videos and also consider a dedicated text search service. For now we use a basic prefix query on “transcription.”

---

### 4. Create a Video Search Results View

Build a new view for displaying video search results in a grid layout. You can reuse your existing `VideoGridView` to lay out thumbnails similarly to the profile page.

```swift
// File: Tiktok/Views/VideoSearchResultsView.swift
import SwiftUI

struct VideoSearchResultsView: View {
    let isLoading: Bool
    let searchQuery: String
    let searchResults: [VideoModel]

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                Text("No videos found")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VideoGridView(videos: .constant(searchResults)) { video in
                    // On tap, navigate to VideoDetailView
                    // You can use a navigationDestination similar to your Profile videos grid
                    // For simplicity, you might want to send a navigation action here
                }
            }
        }
    }
}
```

> **Notes:**
>
> - In this placeholder, the grid uses a constant binding for the results. In a more advanced implementation, you might convert this into a stateful binding so that tapping a video opens a detail view.
> - You can copy the navigation logic from your `PostsGridView` in ProfileView to present a detail view for a selected video.

---

### 5. Update Firestore Rules & Data Structure (Optional)

If you plan to index or search by the “transcription” field, ensure that:

- Videos uploaded already contain a transcription (or use caption as a fallback).
- Firestore indexes are configured for the “transcription” field if you use range queries. (This may require an update in your Firestore indexes file.)

For now, you could add an index for the transcription field in your `firestore.indexes.json`:

```json
{
  "collectionGroup": "videos",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "transcription", "order": "ASCENDING" },
    { "fieldPath": "transcription", "order": "DESCENDING" }
  ]
}
```

---

### 6. Wire It All Together

Make sure that:

- Your navigation flow now points to your new combined search view.
- The dropdown menu correctly toggles between users and videos search.
- The video search view model is called when the user types a query and the results are bound in the grid.
- When a video thumbnail is tapped, you navigate to `VideoDetailView` (reusing your existing navigation code).

---

### 7. Testing

- Verify that when the app is in the search tab, the text field is automatically focused.
- Check that the dropdown lets you switch between “Users” and “Videos.”
- For video searches, type a query that should match the transcription field and verify that the grid layout shows the expected video thumbnails.
- Navigate from a video thumbnail to its detail view, ensuring that any state updates (such as likes/bookmarks) work as expected.

---

This plan makes it so that the search page defaults to users, but by tapping the dropdown the user can switch to video searches. Videos are queried (for now by matching the transcription text) and displayed in a grid similar to that on the profile page. Later you can refine the search algorithm and UI animations as needed.
