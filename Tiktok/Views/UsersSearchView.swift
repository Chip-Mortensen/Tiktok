import SwiftUI
import FirebaseAuth

struct SearchView: View {
    @StateObject private var usersViewModel = UsersSearchViewModel()
    @StateObject private var videoViewModel = VideoSearchViewModel()
    @State private var searchType: SearchType = .users
    @Environment(\.tabSelection) var tabSelection
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    SearchBarView(
                        searchQuery: Binding(
                            get: { searchType == .users ? usersViewModel.searchQuery : videoViewModel.searchQuery },
                            set: { newValue in
                                if searchType == .users {
                                    usersViewModel.searchQuery = newValue
                                } else {
                                    videoViewModel.searchQuery = newValue
                                }
                            }
                        ),
                        onClear: {
                            if searchType == .users {
                                usersViewModel.searchQuery = ""
                                usersViewModel.performSearch()
                            } else {
                                videoViewModel.searchQuery = ""
                                videoViewModel.performSearch()
                            }
                        },
                        onChange: {
                            if searchType == .users {
                                usersViewModel.performSearch()
                            } else {
                                videoViewModel.performSearch()
                            }
                        },
                        focusBinding: $isSearchFieldFocused
                    )

                    // Dropdown to toggle between user and video search
                    Menu {
                        ForEach(SearchType.allCases, id: \.self) { type in
                            Button(type.rawValue) {
                                searchType = type
                                isSearchFieldFocused = true
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.title2)
                    }
                    .padding(.trailing)
                }
                .padding(.horizontal)
                .environment(\.searchType, searchType)

                // Conditional result view based on search type
                if searchType == .users {
                    UsersSearchResultsView(
                        isLoading: usersViewModel.isLoading,
                        searchQuery: usersViewModel.searchQuery,
                        searchResults: usersViewModel.searchResults,
                        tabSelection: tabSelection
                    )
                } else {
                    VideoSearchResultsView(
                        isLoading: videoViewModel.isLoading,
                        searchQuery: videoViewModel.searchQuery,
                        searchResults: videoViewModel.searchResults
                    )
                    .environmentObject(BookmarkService.shared)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // Automatically focus the search field when in the search tab
            if tabSelection.wrappedValue == 1 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                isSearchFieldFocused = true
            }
        }
        .onChange(of: tabSelection.wrappedValue) { _, newValue in
            if newValue == 1 {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    isSearchFieldFocused = true
                }
            } else {
                isSearchFieldFocused = false
            }
        }
    }
}

// MARK: - Search Bar View
private struct SearchBarView: View {
    @Binding var searchQuery: String
    let onClear: () -> Void
    let onChange: () -> Void
    let focusBinding: FocusState<Bool>.Binding
    @Environment(\.searchType) private var searchType
    
    var body: some View {
        HStack(spacing: 12) {
            // Show different icon based on search type
            Image(systemName: searchType == .users ? "person.fill" : "video.fill")
                .foregroundColor(.gray)
            
            TextField(searchType == .users ? "Search users" : "Search videos", text: $searchQuery)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .focused(focusBinding)
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

// Add environment key for search type
private struct SearchTypeKey: EnvironmentKey {
    static let defaultValue: SearchType = .users
}

extension EnvironmentValues {
    var searchType: SearchType {
        get { self[SearchTypeKey.self] }
        set { self[SearchTypeKey.self] = newValue }
    }
}

// MARK: - Search Results View
private struct UsersSearchResultsView: View {
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