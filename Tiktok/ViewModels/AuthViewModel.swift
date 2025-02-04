import Foundation
import FirebaseAuth
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var user: UserModel?
    @Published var isAuthenticated = false
    @Published var error: String?
    
    private let firestoreService = FirestoreService.shared
    private var _authStateHandler: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        _authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser = firebaseUser {
                    do {
                        let user = try await self?.firestoreService.getUser(userId: firebaseUser.uid)
                        self?.user = user
                        self?.isAuthenticated = true
                    } catch {
                        self?.isAuthenticated = false
                        self?.user = nil
                        self?.error = "User data not found. Please sign in again."
                        try? Auth.auth().signOut()
                    }
                } else {
                    self?.isAuthenticated = false
                    self?.user = nil
                }
            }
        }
    }
    
    deinit {
        if let handler = _authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }
    
    func signUp(email: String, password: String, username: String) async {
        do {
            // Validate username
            guard !username.isEmpty else {
                self.error = "Username is required"
                return
            }
            
            // Validate username format
            let usernameRegex = try Regex(#"^[a-zA-Z0-9_.]+$"#)
            guard username.count >= 3,
                  username.count <= 30,
                  username.contains(usernameRegex) else {
                self.error = "Username must be 3-30 characters and can only contain letters, numbers, underscores, and periods."
                return
            }
            
            // Check if username is available
            guard try await firestoreService.isUsernameAvailable(username) else {
                self.error = "Username is already taken"
                return
            }
            
            // Create auth user
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Create user document
            let user = UserModel(
                id: result.user.uid,
                email: email,
                username: username
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