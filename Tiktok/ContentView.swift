//
//  ContentView.swift
//  Tiktok
//
//  Created by Christian Mortensen on 2/3/25.
//

import SwiftUI
import FirebaseAuth
import GoogleSignIn

struct ContentView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isSignUp = false
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isPasswordVisible = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 32) {
                    // Logo/Title
                    VStack(spacing: 12) {
                        Image(systemName: "video.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.blue)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .black.opacity(0.1), radius: 10)
                            )
                        
                        Text("QuikTok")
                            .font(.system(size: 32, weight: .bold))
                        
                        Text(isSignUp ? "Create an account to get started" : "Welcome back")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 20)
                    
                    // Input Fields
                    VStack(spacing: 16) {
                        if isSignUp {
                            // Username field
                            HStack {
                                Image(systemName: "person")
                                    .foregroundColor(.gray)
                                    .frame(width: 24)
                                TextField("Username", text: $username)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 5)
                        }
                        
                        // Email field
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.gray)
                                .frame(width: 24)
                            TextField("Email", text: $email)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 5)
                        
                        // Password field
                        HStack {
                            Image(systemName: "lock")
                                .foregroundColor(.gray)
                                .frame(width: 24)
                            Group {
                                if isPasswordVisible {
                                    TextField("Password", text: $password)
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 5)
                    }
                    .padding(.horizontal)
                    
                    // Error Message
                    if let errorMessage = authViewModel.error {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity)
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
                        .frame(height: 50)
                        .background(
                            isSignUp ? 
                            LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.3), radius: 5)
                    }
                    .disabled(isSignUp && (username.isEmpty || email.isEmpty || password.isEmpty) || 
                             !isSignUp && (email.isEmpty || password.isEmpty))
                    .padding(.horizontal)
                    
                    // Separator
                    HStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                        
                        Text("OR")
                            .font(.footnote)
                            .foregroundColor(.gray)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal)
                    
                    // Google Sign In Button
                    Button {
                        Task {
                            await authViewModel.signInWithGoogle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "g.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.blue)
                            
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 5)
                        .foregroundColor(.black)
                    }
                    .padding(.horizontal)
                    .disabled(authViewModel.isLoading)
                    .overlay {
                        if authViewModel.isLoading {
                            Color.black.opacity(0.1)
                                .cornerRadius(12)
                            ProgressView()
                        }
                    }
                    
                    // Toggle Sign In/Up
                    Button {
                        withAnimation {
                            isSignUp.toggle()
                            authViewModel.error = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                .foregroundColor(.gray)
                            Text(isSignUp ? "Sign In" : "Sign Up")
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                    }
                    
                    Spacer()
                }
                .padding(.top, 40)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
