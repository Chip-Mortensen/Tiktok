Below is a step‐by‐step implementation plan to create a “Users” page where a user can search by username and, when selecting a result, see the same profile popup you already use in the main video feed.

---

## 1. Create the Search UI

**a. New View File:**  
Create a new file (for example, `Tiktok/Views/UsersSearchView.swift`) that contains a view with a search bar and a list of results.

**b. UI Elements:**

- Add a SwiftUI `TextField` at the top to input the username keyword.
- Display the search results using a `List` or `ScrollView`.

**Example:**

```swift
import SwiftUI

struct UsersSearchView: View {
    @StateObject private var viewModel = UsersSearchViewModel()
    @State private var selectedUser: UserModel?

    var body: some View {
        NavigationView {
            VStack {
                TextField("Search by username", text: $viewModel.searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                    .onChange(of: viewModel.searchQuery) { newValue in
                        viewModel.performSearch()
                    }

                if viewModel.isLoading {
                    ProgressView("Searching...")
                } else {
                    List(viewModel.searchResults, id: \.id) { user in
                        UserRowView(user: user) {
                            selectedUser = user
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Find Users")
            .sheet(item: $selectedUser) { user in
                NavigationView {
                    UserProfileView(userId: user.id ?? "")
                }
                .presentationDragIndicator(.visible)
            }
        }
    }
}
```

_Notes:_  
– The sheet presentation reuses the existing `UserProfileView`.  
– The search field calls a method on the view model (see below) when the query changes.

---

## 2. Create the Search ViewModel

**a. New ViewModel File:**  
Create a new file (for example, `Tiktok/ViewModels/UsersSearchViewModel.swift`) that will handle the search logic.

**b. Properties and Firestore Query:**

- Add a `@Published var searchQuery: String` and a `@Published var searchResults: [UserModel]`.
- Optionally include a loading state.

**c. Firestore Query Logic:**

- When the search query is nonempty, run a query against the “users” collection filtering by username.
- Use a “startsWith” pattern by using queries on the username field (for example, using range queries with isGreaterThanOrEqualTo and isLessThan).

**Example:**

```swift
import SwiftUI
import FirebaseFirestore

@MainActor
class UsersSearchViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [UserModel] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()

    /// This method performs a search by username whenever the search query is updated.
    func performSearch() {
        // Prevent unnecessary queries when search query is empty.
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        isLoading = true
        // Create a query for usernames that start with the searchQuery.
        let lowercaseQuery = searchQuery.lowercased()
        // Firestore does not provide a direct "startsWith" implementation.
        // Here we use a range query to get documents where username >= query
        // and username < query + "\u{f8ff}"
        let endQuery = lowercaseQuery + "\u{f8ff}"

        db.collection("users")
            .order(by: "usernameLowercased")
            .whereField("usernameLowercased", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("usernameLowercased", isLessThanOrEqualTo: endQuery)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    print("Search error: \(error.localizedDescription)")
                    self.searchResults = []
                } else if let documents = snapshot?.documents {
                    self.searchResults = documents.compactMap { try? UserModel(document: $0) }
                }
            }
    }
}
```

_Notes:_  
– In this example, we assume that you store a lowercase version of the username (for instance, in a field called `usernameLowercased`) to simplify comparing search queries.  
– Adjust the Firestore query if needed to match your data schema.

---

## 3. Create a Reusable User Row Component

**a. New Component File (Optional):**  
Create a small view called `UserRowView` (you can put this in its own file or in `UsersSearchView.swift`) to display basic user info (profile image, username).

**b. Handle Tap Actions:**  
When a user taps the row, call a closure that sets the selected user (which in turn presents the profile popup).

**Example:**

```swift
import SwiftUI

struct UserRowView: View {
    let user: UserModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if let profileImageUrl = user.profileImageUrl,
                   let url = URL(string: profileImageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                }

                Text("@\(user.username)")
                    .foregroundColor(.primary)
                    .font(.headline)

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
}
```

---

## 4. Reuse the Existing Profile Popup

In the search view, when a row is tapped, the selected user is set and then displayed in a sheet that reuses your already implemented profile view. In the code snippet in **Step 1**, notice:

```swift
.sheet(item: $selectedUser) { user in
    NavigationView {
        UserProfileView(userId: user.id ?? "")
    }
    .presentationDragIndicator(.visible)
}
```

This ensures that when a user is selected from the search results, they see the same profile popup as when tapping on tags in the main video feed.

---

## 5. Integrate the Users Page into Your App

**a. Navigation:**

- Link to the `UsersSearchView` from your main navigation (for example, by adding a “Search” tab or a button in a side menu).

**b. Example Integration in MainTabView (if using tabs):**

```swift
TabView {
    VideoFeedView()
        .tabItem {
            Image(systemName: "house")
            Text("Home")
        }

    UsersSearchView()
        .tabItem {
            Image(systemName: "magnifyingglass")
            Text("Search")
        }

    // Other tabs as needed
}
```

---

## 6. Testing and Verification

- **Search Functionality:** Verify that entering a username (or prefix) correctly fetches and displays matching users.
- **Profile Popup:** Ensure that tapping on a search result brings up the correct profile view.
- **Error Handling:** Add error handling or UI feedback (if needed) in cases where the Firestore query fails or returns no results.
- **Debouncing:** Consider adding a debounce mechanism to the search field to avoid too many rapid-fire queries.

---

By following these steps, you will have a separate “Users” page that allows users to search for others by username and reuses the existing profile popup component to show user details.
