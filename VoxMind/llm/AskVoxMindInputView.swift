import SwiftUI


struct VoxMindAskBar: View {
    var body: some View {
        HStack {
            // 左侧图标 + 提示文字
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.blue)
                Text("向 VoxMind 提问...")
                    .foregroundColor(Color.gray)
                    .font(.system(size: 15))
            }
            .padding(.leading, 12)
            
            Spacer()
            
            // 右侧“历史” + 图标
            HStack(spacing: 4) {
                Text("历史")
                    .foregroundColor(.primary)
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "clock")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(.primary)
            }
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.95))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
