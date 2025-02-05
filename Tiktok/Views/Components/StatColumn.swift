import SwiftUI

struct StatColumn: View {
    let count: Int
    let title: String
    var isEnabled: Bool = true
    var action: (() -> Void)?
    
    var body: some View {
        VStack {
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .opacity(isEnabled ? 1 : 0.6)
        .onTapGesture {
            if isEnabled {
                action?()
            }
        }
    }
} 