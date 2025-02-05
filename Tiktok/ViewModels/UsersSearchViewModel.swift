import SwiftUI
import FirebaseFirestore

@MainActor
class UsersSearchViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [UserModel] = []
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    private var searchTask: Task<Void, Never>?
    
    func performSearch() {
        // Cancel any existing search task
        searchTask?.cancel()
        
        // Create a new search task
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Trim and validate search query
            let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespaces)
            guard !trimmedQuery.isEmpty else {
                await MainActor.run {
                    self.searchResults = []
                    self.isLoading = false
                }
                return
            }
            
            await MainActor.run {
                self.isLoading = true
            }
            
            // Add a small delay to debounce rapid typing
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Check if task was cancelled during the delay
            if Task.isCancelled { return }
            
            do {
                // First try an exact match
                let exactSnapshot = try await db.collection("users")
                    .whereField("username", isEqualTo: trimmedQuery)
                    .limit(to: 20)
                    .getDocuments()
                
                if Task.isCancelled { return }
                
                var users = exactSnapshot.documents.compactMap { try? UserModel(document: $0) }
                
                // If no exact matches, try prefix match
                if users.isEmpty {
                    let prefixSnapshot = try await db.collection("users")
                        .whereField("username", isGreaterThanOrEqualTo: trimmedQuery)
                        .whereField("username", isLessThan: trimmedQuery + "\u{f8ff}")
                        .limit(to: 20)
                        .getDocuments()
                    
                    if Task.isCancelled { return }
                    
                    users = prefixSnapshot.documents.compactMap { try? UserModel(document: $0) }
                }
                
                await MainActor.run {
                    self.searchResults = users
                    self.isLoading = false
                }
            } catch {
                if !Task.isCancelled {
                    print("Search error: \(error.localizedDescription)")
                    await MainActor.run {
                        self.searchResults = []
                        self.isLoading = false
                    }
                }
            }
        }
    }
} 