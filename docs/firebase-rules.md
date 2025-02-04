# Firebase Rules Management

This document outlines how we manage Firebase Security Rules for both Firestore and Storage in this project.

## Overview

Security rules are stored in version control under the `firebase/` directory:

- `firebase/firestore.rules` - Contains Firestore security rules
- `firebase/storage.rules` - Contains Storage security rules

## Deployment

Rules can be deployed using the Firebase CLI:

```bash
# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Storage rules
firebase deploy --only storage:rules
```

## Rules Structure

### Firestore Rules

Our Firestore rules implement the following security model:

1. User Profiles (`/users/{userId}`)

   - Public read access
   - Create allowed for authenticated users
   - Update restricted to own profile

2. Username Management (`/usernames/{username}`)

   - Public read access
   - Create/Update/Delete restricted to username owner
   - Enforces username format and uniqueness

3. Video Content (`/videos/{videoId}`)

   - Public read access
   - Create allowed for authenticated users
   - Update/Delete restricted to video owner

4. Social Features
   - Followers/Following collections with appropriate access controls
   - Public read access for social connections
   - Write access restricted to relevant users

### Storage Rules

Our Storage rules implement the following security model:

1. Video Files (`/videos/{userId}/{videoId}`)

   - Public read access
   - Write access restricted to video owner

2. Thumbnails (`/thumbnails/{userId}/{videoId}`)

   - Public read access
   - Write access restricted to thumbnail owner

3. Profile Images (`/profile-images/{userId}/{imageId}`)
   - Public read access
   - Write access restricted to profile owner
   - 5MB size limit
   - Image file type validation

## Best Practices

1. Always update rules through version control, not the Firebase Console
2. Test rule changes thoroughly before deployment
3. Keep rules as restrictive as possible while maintaining functionality
4. Document significant rule changes in commit messages
5. Use the Firebase Emulator Suite for testing rule changes locally

## Common Operations

### Testing Rules Locally

```bash
firebase emulators:start
```

### Checking Current Rules

```bash
firebase firestore:rules get
firebase storage:rules get
```

### Getting Rule History

```bash
firebase firestore:rules list
firebase storage:rules list
```
