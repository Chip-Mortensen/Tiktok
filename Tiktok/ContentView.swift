//
//  ContentView.swift
//  Tiktok
//
//  Created by Christian Mortensen on 2/3/25.
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isSignUp = false
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        ZStack {
            Color(.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 25) {
                // Logo/Title
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    Text("TikTok Clone")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.bottom, 40)
                
                // Input Fields
                VStack(spacing: 15) {
                    if isSignUp {
                        TextField("Username", text: $username)
                            .textFieldStyle(CustomTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(CustomTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(CustomTextFieldStyle())
                }
                
                // Error Message
                if let errorMessage = authViewModel.error {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Sign In/Up Button
                Button {
                    Task {
                        if isSignUp {
                            await authViewModel.signUp(email: email, password: password, username: username)
                        } else {
                            await authViewModel.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    HStack {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isSignUp && (username.isEmpty || email.isEmpty || password.isEmpty) || 
                         !isSignUp && (email.isEmpty || password.isEmpty))
                
                // Toggle Sign In/Up
                Button {
                    isSignUp.toggle()
                    authViewModel.error = nil
                } label: {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 32)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
