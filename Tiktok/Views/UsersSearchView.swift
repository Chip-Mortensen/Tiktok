import SwiftUI

struct UsersSearchView: View {
    @StateObject private var viewModel = UsersSearchViewModel()
    @State private var selectedUser: UserModel?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search users", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .onChange(of: viewModel.searchQuery) { _ in
                            viewModel.performSearch()
                        }
                    
                    if !viewModel.searchQuery.isEmpty {
                        Button(action: {
                            viewModel.searchQuery = ""
                            viewModel.performSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                
                // Results or Loading State
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No users found")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.searchResults) { user in
                                    UserRowView(user: user) {
                                        selectedUser = user
                                    }
                                    Divider()
                                }
                            }
                            .padding(.top)
                        }
                    }
                }
            }
            .navigationTitle("Find Users")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedUser) { user in
            NavigationView {
                UserProfileView(userId: user.id ?? "")
            }
            .presentationDragIndicator(.visible)
        }
    }
} 