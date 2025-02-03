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
    @State private var message = ""
    
    var body: some View {
        VStack(spacing: 20) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
            
            SecureField("Password", text: $password)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
            
            Button("Sign Up") {
                print("Attempting to sign up with email: \(email)")
                AuthService.shared.signUp(email: email, password: password) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let authResult):
                            message = "Signed up: \(authResult.user.email ?? "")"
                            print("Successfully signed up user: \(authResult.user.uid)")
                        case .failure(let error):
                            message = "Sign up error: \(error.localizedDescription)"
                            print("Sign up error details:")
                            print("Error code: \((error as NSError).code)")
                            print("Error domain: \((error as NSError).domain)")
                            print("Full error: \(error)")
                            let authError = error as NSError
                            switch authError.code {
                            case AuthErrorCode.emailAlreadyInUse.rawValue:
                                message = "This email is already registered. Please try signing in instead."
                            case AuthErrorCode.invalidEmail.rawValue:
                                message = "Please enter a valid email address."
                            case AuthErrorCode.weakPassword.rawValue:
                                message = "Password is too weak. Please use at least 6 characters."
                            default:
                                message = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            Button("Sign In") {
                print("Attempting to sign in with email: \(email)")
                AuthService.shared.signIn(email: email, password: password) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let authResult):
                            message = "Signed in: \(authResult.user.email ?? "")"
                            print("Successfully signed in user: \(authResult.user.uid)")
                        case .failure(let error):
                            message = "Sign in error: \(error.localizedDescription)"
                            print("Sign in error details:")
                            print("Error code: \((error as NSError).code)")
                            print("Error domain: \((error as NSError).domain)")
                            print("Full error: \(error)")
                            let authError = error as NSError
                            switch authError.code {
                            case AuthErrorCode.wrongPassword.rawValue:
                                message = "Incorrect password. Please try again."
                            case AuthErrorCode.userNotFound.rawValue:
                                message = "No account found with this email. Please sign up first."
                            case AuthErrorCode.invalidEmail.rawValue:
                                message = "Please enter a valid email address."
                            default:
                                message = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            Text(message)
                .padding()
                .multilineTextAlignment(.center)
        }
        .padding()
        .onAppear {
            print("Current Firebase Auth state: \(String(describing: Auth.auth().currentUser))")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
