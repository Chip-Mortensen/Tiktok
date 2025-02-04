import Foundation
import UIKit
import FirebaseStorage

@MainActor
final class EditProfileViewModel: ObservableObject {
    @Published var username: String
    @Published var bio: String
    @Published var profileImageUrl: String?
    @Published var errorMessage: String?
    @Published var isSaving = false
    @Published var didUpdate = false
    
    private let user: UserModel
    private let userService = UserService()
    private let storage = Storage.storage().reference()
    
    init(user: UserModel) {
        self.user = user
        self.username = user.username
        self.bio = user.bio ?? ""
        self.profileImageUrl = user.profileImageUrl
    }
    
    func saveChanges() async -> Bool {
        guard !isSaving else { return false }
        
        do {
            // Validate username format
            let usernameRegex = try Regex(#"^[a-zA-Z0-9_.]+$"#)
            guard username.count >= 3,
                  username.count <= 30,
                  username.contains(usernameRegex) else {
                errorMessage = "Username must be 3-30 characters and can only contain letters, numbers, underscores, and periods."
                return false
            }
            
            isSaving = true
            defer { isSaving = false }
            
            // Check if username changed and is available
            if username != user.username {
                guard try await userService.isUsernameAvailable(username) else {
                    errorMessage = "Username is already taken"
                    return false
                }
                try await userService.updateUsername(username, for: user)
            }
            
            // Update other profile information
            if bio != user.bio {
                try await userService.updateProfile(userId: user.id ?? "", data: ["bio": bio])
            }
            
            // Signal that an update occurred
            didUpdate = true
            
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    
    func updateProfileImage(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8),
              let userId = user.id else { return }
        
        do {
            // Create a unique image ID using timestamp
            let imageId = "\(Int(Date().timeIntervalSince1970)).jpg"
            let path = "profile-images/\(userId)/\(imageId)"
            let imageRef = storage.child(path)
            
            // Set metadata
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            // Upload image with metadata
            _ = try await imageRef.putDataAsync(imageData, metadata: metadata)
            let url = try await imageRef.downloadURL()
            
            // Update user profile with new image URL
            try await userService.updateProfile(userId: userId, data: ["profileImageUrl": url.absoluteString])
            
            // Update local state
            profileImageUrl = url.absoluteString
            didUpdate = true
        } catch {
            errorMessage = "Failed to upload image: \(error.localizedDescription)"
            print("DEBUG: Failed to upload profile image with error: \(error.localizedDescription)")
        }
    }
} 