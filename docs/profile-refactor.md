Below is a complete implementation plan to change profile navigation for users other than yourself. Instead of showing the profile as a popup sheet, profiles will now always appear as standard full-page views within the app’s navigation stack. A back button in the navigation bar lets users return to wherever they came from.

---

## 1. Plan Overview

- **Full-Page Navigation:**  
  When a user taps on a profile (for example, from a video feed or a search result) and that profile does not belong to the current user, push a full-page profile view onto the navigation stack instead of presenting a modal sheet.

- **Conditional Navigation:**

  - **Current User:** If the profile belongs to the current user, remain on the profile tab (or switch to it).
  - **Other Users:** If the profile belongs to another user, push a full-page view (using a `NavigationLink` or `navigationDestination`) that includes a standard back button.

- **Global Navigation Consistency:**  
  Wrap the relevant views inside a `NavigationStack` (or `NavigationView` if you are supporting older SwiftUI versions) so that navigation works as expected.

---

## 2. Update the Users Search Flow

### a. Modify the Search View

Instead of showing a profile popup using a sheet, update your search view to use `NavigationLink` in a list. This allows tapping a user row to push the full-page profile view.

_For example, in `Tiktok/Views/UsersSearchView.swift`:_

```swift: Tiktok/Views/UsersSearchView.swift
struct UsersSearchView: View {
    @StateObject private var viewModel = UsersSearchViewModel()

    var body: some View {
        NavigationStack {
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
                        // Use NavigationLink to push the profile view as a full page.
                        NavigationLink(destination: UserProfileView(userId: user.id ?? "")) {
                            UserRowView(user: user)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Find Users")
        }
    }
}
```

### b. Update the User Row Component (Optional)

If not already done, create or update a reusable view component for a single user row (e.g., `UserRowView`). This view simply shows basic user details like the username and profile image.

```swift: Tiktok/Views/Components/UserRowView.swift
struct UserRowView: View {
    let user: UserModel

    var body: some View {
        HStack {
            if let profileImageUrl = user.profileImageUrl, let url = URL(string: profileImageUrl) {
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
```

---

## 3. Update the Video Feed Flow

In the video feed view, a tap on the username should now check if the profile belongs to the current user. If not, use navigation to push a full-page profile view.

### a. Modify the Tap Handler in the Video Feed

In `Tiktok/Views/VideoFeedView.swift`, refactor the username button action. Instead of setting a flag for showing a profile sheet, you will trigger navigation:

```swift: Tiktok/Views/VideoFeedView.swift
// Inside the HStack for video info, replace the current button action:
Button {
    print("DEBUG: Username tapped, showing profile for: \(video.username ?? "unknown")")
    player?.pause()
    isPlaying = false

    if video.userId == Auth.auth().currentUser?.uid {
        // If it's the current user's video, switch to profile tab
        dismiss()
        tabSelection.wrappedValue = 2 // Profile tab
    } else {
        // Instead of showing a modal sheet now, navigate to the profile page.
        // You can set a navigation link active state here or call a coordinator.
        // For example, if you have a NavigationStack higher up:
        NavigationUtil.navigate(to: UserProfileView(userId: video.userId ?? ""))
    }
} label: {
    Text("@\(video.username ?? "user")")
        .font(.headline)
        .foregroundColor(.white)
}
```

> **Note:**  
> The above code snippet uses a hypothetical `NavigationUtil.navigate(to:)` helper. One possible approach is to introduce a navigation coordinator or use a dedicated navigation link that activates when a state variable is updated. Alternatively, if the entire view is embedded in a `NavigationStack`, you can use `navigationDestination` with state-binding.

### b. Implement a Navigation Helper (Optional)

For cleaner code, you may create a helper utility for triggering full-page navigation without a popup. For example:

```swift: Tiktok/Utils/NavigationUtil.swift
import SwiftUI

struct NavigationUtil {
    static func navigate<Destination: View>(to view: Destination) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else {
            return
        }

        let hostingController = UIHostingController(rootView: view)
        root.show(hostingController, sender: nil)
    }
}
```

> **Tip:**  
> Depending on your app’s navigation structure, you might have a dedicated coordinator or simply wrap the parent view with `NavigationStack` and conditionally present `NavigationLink` destinations.

---

## 4. General Navigation Structure

Ensure that the views where the profile is pushed (e.g., search results or video feed) are embedded in a `NavigationStack` (or `NavigationView`). This guarantees that the profile view shows a standard navigation bar with a back button.

For example, in your main tab view, each tab could be wrapped with its own `NavigationStack`:

```swift: Tiktok/Views/MainTabView.swift
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VideoFeedView()
                    .environment(\.tabSelection, $selectedTab)
            }
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }
            .tag(0)

            NavigationStack {
                UsersSearchView()
            }
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("Search")
            }
            .tag(1)

            // For current user, use the profile tab
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Image(systemName: "person")
                Text("Profile")
            }
            .tag(2)
        }
    }
}
```

---

## 5. Testing and Verification

- **Navigation Flow:**  
  Test that tapping on another user's profile opens a full-page view with a back button in the navigation bar.
- **Back Navigation:**  
  Verify that the back button correctly returns the user to the previous view (e.g., search results or video feed).
- **Conditional Logic:**  
  Ensure that tapping on your own username still switches to the profile tab and does not push a duplicate profile view.
- **Overall UX:**  
  Verify that the profile page looks consistent (full page) and that the user experience is intuitive.

---

## 6. Cleanup

- **Remove Popup Code:**  
  Go through your codebase and remove any references to presenting the `UserProfileView` as a sheet for non-current users.
- **Refactor and Comment:**  
  Ensure that your conditional navigation logic (for current versus other users) is clearly commented for maintainability.

---

By following this plan, you will change your app’s behavior so that all profiles (except your own) are viewed as full-page screens with standard navigation, eliminating the modal popup design. Happy coding!
