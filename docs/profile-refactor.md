Below is a detailed implementation plan to convert the “followers,” “following,” and (for your own profile only) “likes” stats into tappable controls that open a popup sheet showing a list of users (each with a profile image):

---

## 1. Overview

When the user taps on either the “Followers” or “Following” count (on any profile) the app should present a popup sheet (using SwiftUI’s `.sheet`) that shows a list of users along with their profile pictures. In addition, if the profile belongs to the current user, the “Likes” stat becomes tappable and shows an analogous sheet. (For privacy reasons, only the owner’s “likes” sheet may be presented.)

---

## 2. Adding Tap Actions to the Stat Views

### a. Define a Sheet Type Enumeration

Create an enumeration that represents which list should be shown. For example:

```swift
enum UserListSheetType {
    case followers, following, likes
}
```

### b. Update the Profile Header

In your profile view (e.g. in `ProfileView.swift` for the logged‐in user and/or in `UserProfileView.swift` for other users) locate the stat row. For instance, you might have three `StatColumn` views for “Following”, “Followers”, and “Likes.” Wrap each stat element in an interactive element (a Button or attach an `onTapGesture`) so that tapping them sets a state variable indicating the sheet type and shows the sheet.

Example in `ProfileView`:

```swift
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var isSheetShowing = false
    @State private var sheetType: UserListSheetType = .followers

    var body: some View {
        VStack {
            // ... your profile header code ...

            HStack(spacing: 32) {
                // Following stat – always tappable for any profile
                StatColumn(count: viewModel.user?.followingCount ?? 0, title: "Following")
                    .onTapGesture {
                        sheetType = .following
                        isSheetShowing = true
                    }

                // Followers stat – always tappable
                StatColumn(count: viewModel.user?.followersCount ?? 0, title: "Followers")
                    .onTapGesture {
                        sheetType = .followers
                        isSheetShowing = true
                    }

                // Likes stat – only if the user is viewing their own profile
                if viewModel.user?.id == Auth.auth().currentUser?.uid {
                    StatColumn(count: viewModel.user?.likesCount ?? 0, title: "Likes")
                        .onTapGesture {
                            sheetType = .likes
                            isSheetShowing = true
                        }
                } else {
                    // If viewing someone else’s profile, you might opt not to make the likes stat tappable,
                    // or even hide it from that context.
                    StatColumn(count: viewModel.user?.likesCount ?? 0, title: "Likes")
                }
            }
        }
        .sheet(isPresented: $isSheetShowing) {
            UserListSheetView(sheetType: sheetType, userId: viewModel.user?.id)
        }
    }
}
```

_Note:_ You might need to have a similar logic in `UserProfileView` if you want the other user’s follower and following stats to also be tappable.

---

## 3. Creating the Popup Sheet View

Create a new reusable view (for example, `UserListSheetView`) that displays a list of users along with their profile picture. This view will be driven by which type of list is requested (followers, following, or likes). You can use a `NavigationView` so that the sheet has a navigation title and a “Done” button to dismiss.

### a. Defining the New Sheet View

```swift
import SwiftUI

struct UserListSheetView: View {
    let sheetType: UserListSheetType
    // The userId parameter determines whose list to fetch.
    // For "likes" this should be the current user’s id.
    let userId: String?

    // Local state for the fetched users
    @State private var users: [UserModel] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var title: String {
        switch sheetType {
        case .followers:
            return "Followers"
        case .following:
            return "Following"
        case .likes:
            return "Likes"
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading \(title)...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if users.isEmpty {
                    Text("No \(title.lowercased()) found.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(users) { user in
                        HStack(spacing: 12) {
                            if let profileImageUrl = user.profileImageUrl, let url = URL(string: profileImageUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                        .scaledToFill()
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
                                .font(.headline)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchUserList()
            }
        }
    }

    func fetchUserList() {
        guard let userId = userId else { return }
        isLoading = true

        // Based on the sheet type, call the corresponding FirestoreService method:
        // (These methods are assumed to exist or you may need to implement them accordingly.)
        Task {
            do {
                switch sheetType {
                case .followers:
                    // Get list of followers
                    users = try await FirestoreService.shared.getFollowers(forUserId: userId)
                case .following:
                    // Get list of following users
                    users = try await FirestoreService.shared.getFollowing(forUserId: userId)
                case .likes:
                    // For likes: This may require a new Firestore query to fetch the list
                    // of users who have liked the current user’s content. This feature might need backend support.
                    users = try await FirestoreService.shared.getUsersWhoLikedContent(forUserId: userId)
                }
            } catch {
                print("Error fetching \(title) list: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}
```

**Notes:**

- The view above assumes that you have (or will create) corresponding methods in your Firestore service layer. Currently you already have `getFollowers(forUserId:)` and `getFollowing(forUserId:)`. For likes, you may need a new method (for example, `getUsersWhoLikedContent(forUserId:)`) that aggregates which users have “liked” your posts.
- If you prefer a “pull-to-refresh” functionality inside the sheet, you can wrap the list in a `List` with a `.refreshable` modifier.

---

## 4. Firestore Service Adjustments

### a. Verify or Implement Methods

Make sure that your Firestore service (for example, in `FirestoreService.swift`) has methods to fetch:

- Followers: `func getFollowers(forUserId: String) async throws -> [UserModel]`
- Following: `func getFollowing(forUserId: String) async throws -> [UserModel]`
- Likes: If it does not exist, implement a similar function:

  For example, if your backend stores likes in a collection (perhaps under a “userLikes” document or within each video’s subcollection), then add:

  ```swift
  func getUsersWhoLikedContent(forUserId userId: String) async throws -> [UserModel] {
      // Example implementation:
      // 1. Query your 'likes' collection or aggregate data from each post.
      // 2. Map the resulting liker IDs into UserModel objects using a method such as `getUser(withId:)`.
      // This may require additional backend design.
  }
  ```

- Adjust security rules as needed to allow read access only to the appropriate users (remember: only the current user should be allowed to see their own likes list).

---

## 5. Testing and Edge Cases

- **Testing the Sheets:**  
  • Tap on the “Followers” and “Following” stats on both other users’ profiles and your own profile.  
  • Verify that the popup sheet displays a list of users (including the profile image and username).  
  • For the “Likes” stat, ensure that it only appears as a tappable element on your own profile.
- **Loading and Error States:**  
  • Show a loading indicator (using a `ProgressView`) while fetching data.  
  • Handle an empty list gracefully by displaying an appropriate message.
- **Navigation and Dismissal:**  
  • Include a “Done” or “Close” button in the sheet’s navigation bar to dismiss the sheet cleanly.

---

## 6. Code Review and Cleanup

- **Refactor Common Code:** Consider extracting common UI elements (e.g., a generic user row view) so that the new sheet can reuse your existing `UserRowView` or similar assets.
- **Comments:** Add clear comments explaining your conditional logic (especially why the “Likes” sheet appears only on your own profile).
- **Remove Legacy Code:** Once the old modal approaches (if any) are no longer needed, clean up the codebase.

---

## 7. Summary

With these changes you will convert your profile header’s stat counts into interactive elements that present a full-screen or modal popup sheet listing the relevant users. You’ll be:

- Capturing tap events on the “Followers,” “Following,” and (conditionally) “Likes” stats.
- Presenting a dedicated sheet view that loads the corresponding list via your Firestore service.
- Ensuring that privacy is maintained by restricting the “Likes” list to only the current user’s view.

Happy coding!
