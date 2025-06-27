import SwiftUI

//挂件列表视图
struct LifeLogListView: View {
    var body: some View {
        NavigationView {
            LimitlessLifelogsView()
                .navigationTitle("挂件")
                .navigationBarTitleDisplayMode(.inline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }
}
