import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showUploadVideo = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                VideoFeedView()
                    .tabItem {
                        Image(systemName: "house")
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
                
                Text("Profile")
                    .tabItem {
                        Image(systemName: "person")
                        Text("Profile")
                    }
                    .tag(2)
            }
            .sheet(isPresented: $showUploadVideo) {
                VideoUploadView()
            }
            
            // Custom tab bar background that extends below safe area
            VStack {
                Spacer()
                Rectangle()
                    .fill(.white)
                    .frame(height: 49 + (UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0))
                    .ignoresSafeArea()
            }
            .allowsHitTesting(false) // Allow interaction with tab bar items
        }
        .onAppear {
            // Set tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
} 