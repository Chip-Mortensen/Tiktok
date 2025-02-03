import Foundation
import FirebaseAuth
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var user: UserModel?
    @Published var isAuthenticated = false
    @Published var error: String?
    
    private let firestoreService = FirestoreService.shared
    
    init() {
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser = firebaseUser {
                    do {
                        let user = try await self?.firestoreService.getUser(userId: firebaseUser.uid)
                        self?.user = user
                        self?.isAuthenticated = true
                    } catch {
                        // If user doesn't exist in Firestore, create it
                        if let email = firebaseUser.email {
                            let newUser = UserModel(
                                id: firebaseUser.uid,
                                username: email,
                                email: email
                            )
                            try? await self?.firestoreService.createUser(newUser)
                            self?.user = newUser
                            self?.isAuthenticated = true
                        } else {
                            self?.isAuthenticated = false
                            self?.user = nil
                            self?.error = "Failed to get user email"
                        }
                    }
                } else {
                    self?.isAuthenticated = false
                    self?.user = nil
                }
            }
        }
    }
    
    func signUp(email: String, password: String, username: String) async {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let user = UserModel(
                id: result.user.uid,
                username: email,
                email: email
            )
            try await firestoreService.createUser(user)
            self.user = user
            self.isAuthenticated = true
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func signIn(email: String, password: String) async {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await fetchUser(userId: result.user.uid)
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.user = nil
            self.isAuthenticated = false
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func fetchUser(userId: String) async {
        do {
            let user = try await firestoreService.getUser(userId: userId)
            self.user = user
            self.isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
            self.isAuthenticated = false
        }
    }
} 