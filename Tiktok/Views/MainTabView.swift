import SwiftUI

private struct TabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var tabSelection: Binding<Int> {
        get { self[TabSelectionKey.self] }
        set { self[TabSelectionKey.self] = newValue }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var appState = AppState.shared
    @StateObject private var bookmarkService = BookmarkService.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VideoFeedView()
                    .environment(\.tabSelection, $selectedTab)
                    .environmentObject(bookmarkService)
            }
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }
            .tag(0)
            
            NavigationStack {
                SearchView()
                    .environment(\.tabSelection, $selectedTab)
            }
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("Search")
            }
            .tag(1)
            
            NavigationStack {
                VideoUploadView()
                    .environment(\.tabSelection, $selectedTab)
            }
            .tabItem {
                Image(systemName: "plus")
                Text("Upload")
            }
            .tag(2)
            
            NavigationStack {
                ProfileView()
                    .environment(\.tabSelection, $selectedTab)
                    .environmentObject(bookmarkService)
            }
            .tabItem {
                Image(systemName: "person")
                Text("Profile")
            }
            .tag(3)
        }
        .environmentObject(appState)
        .onAppear {
            // Start listening for bookmarks
            bookmarkService.startListening()
            
            // Set tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground() // Use default background instead of opaque
            appearance.backgroundColor = .white
            
            // Configure tab bar item appearance for different states
            let itemAppearance = UITabBarItemAppearance()
            
            // Normal state
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.darkGray,
                .font: UIFont.systemFont(ofSize: 11, weight: .medium)
            ]
            itemAppearance.normal.iconColor = .darkGray
            
            // Selected state
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.systemBlue,
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
            ]
            itemAppearance.selected.iconColor = .systemBlue
            
            // Apply the item appearance to all layouts
            appearance.stackedLayoutAppearance = itemAppearance
            appearance.inlineLayoutAppearance = itemAppearance
            appearance.compactInlineLayoutAppearance = itemAppearance
            
            // Apply the appearance to both standard and scroll edge appearances
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
} 