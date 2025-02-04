# User Profile & Following System Implementation Plan

## 1. Database Schema

1. Add following collection:

   ```
   following/{userId}/following/{followedUserId}
     - timestamp: Date
   ```

2. Update user document counters:

   ```
   users/{userId}
     - followingCount: number
     - followersCount: number
   ```

3. Security rules:
   ```
   match /following/{userId}/following/{followedId} {
     allow read;
     allow write: if request.auth != null && request.auth.uid == userId;
   }
   ```

## 2. User Profile Navigation

1. Profile Discovery:

   - Make usernames in video feed tappable
   - Navigate to user profile when username is tapped
   - Pass userId through navigation

2. User Profile View:
   - Create new UserProfileView for viewing other users
   - Share layout with current ProfileView but:
     - Replace edit button with follow/unfollow
     - Hide private features (liked videos tab)
     - Show following status
   - Handle viewing own profile case

## 3. Following System

1. FirestoreService Extensions:

   ```swift
   // Core following operations
   func followUser(userId: String) async throws
   func unfollowUser(userId: String) async throws
   func isFollowingUser(userId: String) async throws -> Bool

   // Real-time updates
   func addFollowingStatusListener(userId: String) -> ListenerRegistration

   // Queries
   func getFollowers(forUserId: String) async throws -> [UserModel]
   func getFollowing(forUserId: String) async throws -> [UserModel]
   ```

2. UserProfileViewModel:
   - Track following status
   - Handle follow/unfollow actions
   - Update counters optimistically
   - Manage error states and rollbacks
   - Cache following status

## 4. Implementation Steps

1. Database Layer:

   - Set up following collection
   - Add following methods to FirestoreService
   - Implement counter updates using transactions

2. View Layer:

   - Create UserProfileView
   - Add username navigation in VideoContent
   - Implement follow button with states
   - Add loading and error states

3. ViewModel Layer:
   - Create UserProfileViewModel
   - Implement following status management
   - Add real-time updates
   - Handle optimistic updates

## 5. Technical Considerations

1. Performance:

   - Use transactions for counter updates
   - Cache following status locally
   - Implement pagination for followers/following lists

2. Error Handling:

   - Handle network failures gracefully
   - Provide clear error messages
   - Implement retry mechanisms

3. Edge Cases:
   - Prevent self-following
   - Handle deleted user accounts
   - Manage concurrent follow/unfollow attempts
   - Handle blocked users (future feature)
