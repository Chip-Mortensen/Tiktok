import SwiftUI
import FirebaseAuth

struct UsersSearchView: View {
    @StateObject private var viewModel = UsersSearchViewModel()
    @Environment(\.tabSelection) var tabSelection
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBarView(
                    searchQuery: $viewModel.searchQuery,
                    onClear: {
                        viewModel.searchQuery = ""
                        viewModel.performSearch()
                    },
                    onChange: {
                        viewModel.performSearch()
                    }
                )
                
                SearchResultsView(
                    isLoading: viewModel.isLoading,
                    searchQuery: viewModel.searchQuery,
                    searchResults: viewModel.searchResults,
                    tabSelection: tabSelection
                )
            }
            .navigationTitle("Find Users")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Search Bar View
private struct SearchBarView: View {
    @Binding var searchQuery: String
    let onClear: () -> Void
    let onChange: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search users", text: $searchQuery)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .onChange(of: searchQuery) { _, _ in
                    onChange()
                }
            
            if !searchQuery.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - Search Results View
private struct SearchResultsView: View {
    let isLoading: Bool
    let searchQuery: String
    let searchResults: [UserModel]
    let tabSelection: Binding<Int>
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                EmptyResultsView()
            } else {
                UserListView(searchResults: searchResults, tabSelection: tabSelection)
            }
        }
    }
}

// MARK: - Empty Results View
private struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("No users found")
                .font(.headline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - User List View
private struct UserListView: View {
    let searchResults: [UserModel]
    let tabSelection: Binding<Int>
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { user in
                    UserRowContent(user: user, tabSelection: tabSelection)
                    Divider()
                }
            }
            .padding(.top)
        }
    }
}

// MARK: - User Row Content
private struct UserRowContent: View {
    let user: UserModel
    let tabSelection: Binding<Int>
    
    var body: some View {
        Group {
            if let userId = user.id {
                if userId == Auth.auth().currentUser?.uid {
                    Button {
                        tabSelection.wrappedValue = 3  // switch to the Profile tab
                    } label: {
                        UserRowView(user: user)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    NavigationLink(destination: UserProfileView(userId: userId)) {
                        UserRowView(user: user)
                    }
                }
            }
        }
    }
} 