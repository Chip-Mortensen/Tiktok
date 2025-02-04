import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showUploadVideo = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            VideoFeedView()
                .tabItem {
                    Image(systemName: "house")
                        .environment(\.symbolVariants, selectedTab == 0 ? .fill : .none)
                    Text("Home")
                }
                .tag(0)
            
            Button(action: { showUploadVideo = true }) {
                Image(systemName: "plus.square")
                    .font(.system(size: 24))
            }
            .tabItem {
                Image(systemName: "plus")
                Text("Upload")
            }
            .tag(1)
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person")
                        .environment(\.symbolVariants, selectedTab == 2 ? .fill : .none)
                    Text("Profile")
                }
                .tag(2)
        }
        .sheet(isPresented: $showUploadVideo) {
            VideoUploadView()
        }
        .onAppear {
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