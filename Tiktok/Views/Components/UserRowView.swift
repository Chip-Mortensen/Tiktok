import SwiftUI

struct UserRowView: View {
    let user: UserModel
    
    var body: some View {
        HStack {
            if let profileImageUrl = user.profileImageUrl, 
               let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(user.username)")
                    .foregroundColor(.primary)
                    .font(.headline)
                
                Text(user.email)
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.system(size: 14))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
} 