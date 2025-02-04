import Foundation

@MainActor
class AppState: ObservableObject {
    @Published var isMuted: Bool = true  // Default to muted
    
    static let shared = AppState()
    private init() {}
} 