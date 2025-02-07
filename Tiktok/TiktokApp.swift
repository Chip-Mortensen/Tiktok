//
//  TiktokApp.swift
//  Tiktok
//
//  Created by Christian Mortensen on 2/3/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@main
struct TiktokApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var appState = AppState.shared
    @StateObject private var videoService = VideoService.shared
    @StateObject private var authService = AuthService()
    
    init() {
        FirebaseApp.configure()
        
        // Configure Google Sign In
        guard let clientId = FirebaseApp.app()?.options.clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated && authViewModel.user != nil {
                    MainTabView()
                        .environmentObject(authViewModel)
                        .environmentObject(appState)
                        .environmentObject(videoService)
                        .environmentObject(authService)
                } else {
                    ContentView()
                        .environmentObject(authViewModel)
                        .environmentObject(appState)
                        .environmentObject(videoService)
                        .environmentObject(authService)
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}