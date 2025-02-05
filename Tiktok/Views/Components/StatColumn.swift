import SwiftUI

struct StatColumn: View {
    let count: Int
    let title: String
    
    var body: some View {
        VStack {
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
} 