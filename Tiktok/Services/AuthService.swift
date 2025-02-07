import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import UIKit

@MainActor
class AuthService: ObservableObject {
    @Published var userSession: FirebaseAuth.User?
    
    private let userService = UserService()
    
    init() {
        self.userSession = Auth.auth().currentUser
    }
    
    func signIn(withEmail email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.userSession = result.user
        } catch {
            print("DEBUG: Failed to sign in with error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "AuthService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to get client ID"
            ])
        }
        
        // Get the current window scene and root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw NSError(domain: "AuthService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to get root view controller"
            ])
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Start Google Sign In flow
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        
        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "AuthService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to get ID token"
            ])
        }
        
        // Create Firebase credential
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        
        // Sign in to Firebase
        let authResult = try await Auth.auth().signIn(with: credential)
        self.userSession = authResult.user
        
        // Generate a valid username from Google profile
        let googleName = result.user.profile?.name ?? ""
        let validUsername = generateValidUsername(from: googleName)
        
        // Check if username is available, if not, append numbers until we find one
        var finalUsername = validUsername
        var counter = 1
        while !(try await userService.isUsernameAvailable(finalUsername)) {
            finalUsername = "\(validUsername)\(counter)"
            counter += 1
        }
        
        // Create or update user document
        let user = UserModel(
            id: authResult.user.uid,
            email: authResult.user.email ?? "",
            username: finalUsername,
            profileImageUrl: result.user.profile?.imageURL(withDimension: 200)?.absoluteString,
            createdAt: Date()
        )
        
        // Start a batch write
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // Set user document
        let userRef = db.collection("users").document(authResult.user.uid)
        batch.setData(user.toDictionary(), forDocument: userRef, merge: true)
        
        // Reserve username
        let usernameRef = db.collection("usernames").document(finalUsername.lowercased())
        batch.setData([
            "userId": user.id ?? "",
            "username": finalUsername,
            "createdAt": Timestamp()
        ], forDocument: usernameRef)
        
        // Commit the batch
        try await batch.commit()
    }
    
    // Helper function to generate valid username
    private func generateValidUsername(from name: String) -> String {
        // Remove spaces and special characters, convert to lowercase
        let validCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        let processed = name.lowercased()
            .filter { validCharacters.contains($0) || $0 == " " }
            .replacingOccurrences(of: " ", with: "_")
        
        // If the processed string is empty or too short, use a default
        if processed.count < 3 {
            return "user_\(Int.random(in: 1000...9999))"
        }
        
        // Truncate if too long
        let maxLength = 30
        if processed.count > maxLength {
            let index = processed.index(processed.startIndex, offsetBy: maxLength)
            return String(processed[..<index])
        }
        
        return processed
    }
    
    func createUser(email: String, password: String, username: String) async throws {
        do {
            // First check if username is available
            guard try await userService.isUsernameAvailable(username) else {
                throw NSError(domain: "AuthService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Username is already taken"
                ])
            }
            
            // Create auth user
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            self.userSession = result.user
            
            // Create user document
            let user = UserModel(
                id: result.user.uid,
                email: email,
                username: username,
                createdAt: Date()
            )
            
            // Start a batch write
            let db = Firestore.firestore()
            let batch = db.batch()
            
            // Set user document
            let userRef = db.collection("users").document(result.user.uid)
            batch.setData(user.toDictionary(), forDocument: userRef)
            
            // Reserve username (no need to check if empty since it's validated in the view)
            let usernameRef = db.collection("usernames").document(username.lowercased())
            batch.setData([
                "userId": result.user.uid,
                "username": username,
                "createdAt": Timestamp()
            ], forDocument: usernameRef)
            
            // Commit both operations
            try await batch.commit()
            
        } catch {
            // If anything fails, delete the auth user if it was created
            if let user = Auth.auth().currentUser {
                try? await user.delete()
            }
            
            print("DEBUG: Failed to create user with error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.userSession = nil
        } catch {
            print("DEBUG: Failed to sign out with error: \(error.localizedDescription)")
        }
    }
    
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            let db = Firestore.firestore()
            let batch = db.batch()
            
            // Get current user data to find username
            let userData = try? await db.collection("users").document(user.uid).getDocument()
            if let username = userData?.data()?["username"] as? String {
                // Delete username reservation
                let usernameRef = db.collection("usernames").document(username.lowercased())
                batch.deleteDocument(usernameRef)
            }
            
            // Delete user document
            let userRef = db.collection("users").document(user.uid)
            batch.deleteDocument(userRef)
            
            // Commit Firestore changes
            try await batch.commit()
            
            // Delete auth user
            try await user.delete()
            
            self.userSession = nil
        } catch {
            print("DEBUG: Failed to delete account with error: \(error.localizedDescription)")
            throw error
        }
    }
} 