//
//  TiktokApp.swift
//  Tiktok
//
//  Created by Christian Mortensen on 2/3/25.
//

import SwiftUI
import Firebase
import FirebaseAuth

@main
struct TikTokApp: App {
    // Initialize Firebase in the init
    init() {
        print("Configuring Firebase...")
                FirebaseApp.configure()
        print("Firebase configured successfully")
            if let currentUser = Auth.auth().currentUser {
                print("Current user is already signed in: \(currentUser.uid)")
            } else {
                print("No user currently signed in")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}