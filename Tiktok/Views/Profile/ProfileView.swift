import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedTab = 0
    @State private var showEditProfile = false
    @State private var showSettings = false
    @State private var bio = ""
    @State private var activeSheet: UserListSheetType?
    
    var body: some View {
        VStack(spacing: 0) {
            // Profile Header
            VStack(spacing: 16) {
                // Profile Image
                if let profileImageUrl = viewModel.user?.profileImageUrl {
                    AsyncImage(url: URL(string: profileImageUrl)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 96, height: 96)
                    }
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 96, height: 96)
                }
                
                // Username
                Text(viewModel.user?.username ?? "")
                    .font(.headline)
                
                // Stats Row
                HStack(spacing: 32) {
                    StatColumn(count: viewModel.user?.followingCount ?? 0, 
                             title: "Following",
                             action: { activeSheet = .following })
                    
                    StatColumn(count: viewModel.user?.followersCount ?? 0, 
                             title: "Followers",
                             action: { activeSheet = .followers })
                    
                    StatColumn(count: viewModel.user?.likesCount ?? 0, 
                             title: "Likes",
                             action: { activeSheet = .likes })
                }
                
                // Bio
                if let bio = viewModel.user?.bio {
                    Text(bio)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .padding(.horizontal)
            
            // Tab Bar
            ProfileTabBar(selectedTab: $selectedTab)
            
            // Tab View for Posts and Liked Posts
            TabView(selection: $selectedTab) {
                PostsGridView(viewModel: viewModel)
                    .tag(0)
                
                LikedPostsGridView(viewModel: viewModel)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showEditProfile = true
                    } label: {
                        Label("Edit Profile", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        viewModel.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.circle")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.black)
                }
            }
        }
        .sheet(item: $activeSheet) { sheetType in
            if let userId = viewModel.user?.id {
                UserListSheetView(sheetType: sheetType, userId: userId)
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let user = viewModel.user {
                EditProfileView(user: user) {
                    // Refresh callback
                    Task {
                        await viewModel.fetchUserData()
                    }
                }
            }
        }
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EditProfileViewModel
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    let onUpdate: () -> Void
    
    init(user: UserModel, onUpdate: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(user: user))
        self.onUpdate = onUpdate
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    // Profile Image
                    HStack {
                        Spacer()
                        Button {
                            showImagePicker = true
                        } label: {
                            if let selectedImage = selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                            } else if let profileImageUrl = viewModel.profileImageUrl,
                                      let url = URL(string: profileImageUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 96, height: 96)
                                }
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 96, height: 96)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .foregroundColor(.white)
                                    }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                
                Section("Profile Information") {
                    TextField("Username", text: $viewModel.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Bio", text: $viewModel.bio)
                        .autocapitalization(.sentences)
                }
                
                if viewModel.errorMessage != nil {
                    Section {
                        Text(viewModel.errorMessage ?? "")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            if await viewModel.saveChanges() {
                                onUpdate()
                                dismiss()
                            }
                        }
                    }
                    .bold()
                    .disabled(viewModel.isSaving)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { oldImage, newImage in
                if let image = newImage {
                    Task {
                        await viewModel.updateProfileImage(image)
                        if viewModel.didUpdate {
                            onUpdate()
                        }
                    }
                }
            }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.editedImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
    }
}

struct ProfileTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            Button {
                selectedTab = 0
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "grid")
                        .font(.title2)
                    Text("Posts")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(selectedTab == 0 ? .black : .gray)
                .padding(.vertical, 8)
            }
            .overlay(alignment: .bottom) {
                if selectedTab == 0 {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 2)
                }
            }
            
            Button {
                selectedTab = 1
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "heart")
                        .font(.title2)
                    Text("Liked")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(selectedTab == 1 ? .black : .gray)
                .padding(.vertical, 8)
            }
            .overlay(alignment: .bottom) {
                if selectedTab == 1 {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 2)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
        }
    }
}

struct PostsGridView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var selectedVideoIndex: Int?
    
    var body: some View {
        let posts = viewModel.posts
        VideoGridView(videos: .constant(posts)) { video in
            if let index = posts.firstIndex(where: { $0.id == video.id }) {
                selectedVideoIndex = index
            }
        }
        .sheet(item: Binding(
            get: { selectedVideoIndex.map { Index(int: $0) } },
            set: { selectedVideoIndex = $0?.int }
        )) { index in
            if let video = posts[safe: index.int] {
                VideoDetailView(video: Binding(
                    get: { video },
                    set: { newValue in
                        viewModel.videoCache[newValue.id] = newValue
                    }
                ))
                .environmentObject(viewModel)
            }
        }
    }
}

struct LikedPostsGridView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var selectedVideoIndex: Int?
    
    var body: some View {
        let likedPosts = viewModel.likedPosts
        VideoGridView(videos: .constant(likedPosts)) { video in
            if let index = likedPosts.firstIndex(where: { $0.id == video.id }) {
                selectedVideoIndex = index
            }
        }
        .sheet(item: Binding(
            get: { selectedVideoIndex.map { Index(int: $0) } },
            set: { selectedVideoIndex = $0?.int }
        )) { index in
            if let video = likedPosts[safe: index.int] {
                VideoDetailView(video: Binding(
                    get: { video },
                    set: { newValue in
                        viewModel.videoCache[newValue.id] = newValue
                    }
                ))
                .environmentObject(viewModel)
            }
        }
    }
}

// Helper struct to make Int identifiable for sheet presentation
private struct Index: Identifiable {
    let int: Int
    var id: Int { int }
} 