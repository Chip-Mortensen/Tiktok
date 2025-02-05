import SwiftUI

struct CommentsCountBadgeView: View {
    @StateObject private var viewModel: CommentsCountViewModel
    
    init(videoId: String) {
        _viewModel = StateObject(wrappedValue: CommentsCountViewModel(videoId: videoId))
    }
    
    var body: some View {
        Text("\(viewModel.count)")
            .font(.caption)
            .foregroundColor(.white)
    }
} 