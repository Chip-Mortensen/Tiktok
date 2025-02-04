import Foundation
import FirebaseAuth
import FirebaseFirestore

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
            
            // Reserve username
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
            if let userData = try? await db.collection("users").document(user.uid).getDocument(),
               let username = userData.data()?["username"] as? String {
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