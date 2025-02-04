//
//  TiktokApp.swift
//  Tiktok
//
//  Created by Christian Mortensen on 2/3/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct TiktokApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var appState = AppState.shared
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated && authViewModel.user != nil {
                    MainTabView()
                        .environmentObject(authViewModel)
                        .environmentObject(appState)
                } else {
                    ContentView()
                        .environmentObject(authViewModel)
                        .environmentObject(appState)
                }
            }
        }
    }
}