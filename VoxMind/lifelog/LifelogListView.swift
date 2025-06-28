import SwiftUI

//挂件列表视图
struct LifeLogListView: View {
    @State private var lifelogs: [Lifelog] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部栏
                HStack {
                    Spacer()
                    
                    // 中间的日期显示
                    Button(action: { showDatePicker = true }) {
                        Text(dateDisplayString(selectedDate))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // 右侧按钮组
                    HStack(spacing: 16) {
                        // 日历按钮
                        Button(action: { showDatePicker = true }) {
                            Image(systemName: "calendar")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                        }
                        
                        // 刷新按钮
                        Button(action: refreshLifelogs) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .rotationEffect(.degrees(isLoading ? 360 : 0))
                                .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                        }
                        .disabled(isLoading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.background)
                
                Divider()
                
                // 主要内容区域
                if isLoading && lifelogs.isEmpty {
                    Spacer()
                    ProgressView("正在加载...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack {
                        Text("❌ 加载失败")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if lifelogs.isEmpty {
                    Spacer()
                    VStack {
                        Text("📝 暂无记录")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("选择不同的日期查看记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    // 生活日志列表
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lifelogs, id: \.id) { lifelog in
                                LifelogCardView(lifelog: lifelog)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .refreshable {
                        await refreshLifelogsAsync()
                    }
                }
            }
            .background(.background.secondary)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationView {
                VStack {
                    DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .onChange(of: selectedDate) { _ in
                            // 选择日期后立即加载数据，无需确定按钮
                            showDatePicker = false
                            refreshLifelogs()
                        }
                    Spacer()
                }
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("取消") {
                            showDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            refreshLifelogs()
        }
    }
    
    private func dateDisplayString(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
    
    private func refreshLifelogs() {
        Task {
            await refreshLifelogsAsync()
        }
    }
    
    @MainActor
    private func refreshLifelogsAsync() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedLifelogs = try await fetchLifelogs(for: selectedDate)
            lifelogs = fetchedLifelogs
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func fetchLifelogs(for date: Date) async throws -> [Lifelog] {
        let apiKey = UserDefaults.standard.string(forKey: "LimitlessAIAPIKey") ?? ""
        guard !apiKey.isEmpty else {
            throw LifelogError.noAPIKey
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        
        let urlString = "https://api.limitless.ai/v1/lifelogs?date=\(dateString)&includeMarkdown=true&includeHeadings=true&limit=50"
        
        guard let url = URL(string: urlString) else {
            throw LifelogError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LifelogError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LifelogError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        do {
            let decoder = JSONDecoder()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            decoder.dateDecodingStrategy = .formatted(dateFormatter)
            
            let response = try decoder.decode(LifelogsResponse.self, from: data)
            return response.data?.lifelogs ?? []
        } catch {
            throw LifelogError.decodingError(error.localizedDescription)
        }
    }
}

// MARK: - 生活日志卡片视图
struct LifelogCardView: View {
    let lifelog: Lifelog
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lifelog.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    HStack {
                        if let startTime = lifelog.startTime {
                            Text(formatTime(startTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let endTime = lifelog.endTime {
                            Text("- \(formatTime(endTime))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if lifelog.isStarred == true {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 内容区域（可展开）
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lifelog.contents ?? [], id: \.hashValue) { content in
                        ContentNodeView(node: content, level: 0)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
         .background(.background)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func formatTime(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "HH:mm"
        
        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - 内容节点视图（树状结构）
struct ContentNodeView: View {
    let node: ContentNode
    let level: Int
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // 根据层级添加缩进
                if level > 0 {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: CGFloat(level * 12))
                }
                
                // 显示图标或箭头
                nodeIconView
                
                // 根据节点类型显示不同的样式
                nodeContentView
                
                Spacer()
            }
            
            // 递归显示子节点（如果展开且有子节点）
            if isExpanded, let children = node.children, !children.isEmpty {
                ForEach(children, id: \.hashValue) { child in
                    ContentNodeView(node: child, level: level + 1)
                }
            }
        }
    }
    
    @ViewBuilder
    private var nodeIconView: some View {
        switch node.type {
        case "heading1":
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
                .font(.system(size: 14))
                
        case "heading2":
            if hasChildren {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                }
            } else {
                Image(systemName: "h2.square")
                    .foregroundColor(.blue)
                    .font(.system(size: 12))
            }
                
        case "heading3":
            if hasChildren {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                }
            } else {
                Image(systemName: "h3.square")
                    .foregroundColor(.blue)
                    .font(.system(size: 12))
            }
                
        case "blockquote":
            Image(systemName: "quote.bubble")
                .foregroundColor(.orange)
                .font(.system(size: 12))
                
        case "paragraph":
            Image(systemName: "text.alignleft")
                .foregroundColor(.gray)
                .font(.system(size: 12))
                
        default:
            Image(systemName: "circle.fill")
                .foregroundColor(.gray)
                .font(.system(size: 8))
        }
    }
    
    private var hasChildren: Bool {
        return node.children?.isEmpty == false
    }
    
    @ViewBuilder
    private var nodeContentView: some View {
        switch node.type {
        case "heading1":
            Text(node.content)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
        case "heading2":
            Text(node.content)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
        case "heading3":
            Text(node.content)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
        case "blockquote":
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.content)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    if let speaker = node.speakerName, !speaker.isEmpty {
                        Text("— \(speaker)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.leading, 8)
                                      .background(.gray.opacity(0.1))
            .cornerRadius(6)
            
        case "paragraph":
            Text(node.content)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
        default:
            Text(node.content)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - 数据模型
struct Lifelog: Identifiable, Decodable {
    let id: String
    let title: String
    let markdown: String?
    let contents: [ContentNode]?
    let startTime: String?
    let endTime: String?
    let isStarred: Bool?
    let updatedAt: String?
}

struct ContentNode: Decodable, Hashable {
    let type: String
    let content: String
    let startTime: String?
    let endTime: String?
    let startOffsetMs: Int?
    let endOffsetMs: Int?
    let children: [ContentNode]?
    let speakerName: String?
    let speakerIdentifier: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(content)
        hasher.combine(startTime)
        hasher.combine(endTime)
    }
}

struct LifelogsResponse: Decodable {
    let data: LifelogsData?
    let meta: MetaInfo?
    
    struct LifelogsData: Decodable {
        let lifelogs: [Lifelog]
    }
    
    struct MetaInfo: Decodable {
        let lifelogs: MetaLifelogs?
        
        struct MetaLifelogs: Decodable {
            let nextCursor: String?
            let count: Int?
        }
    }
}

// MARK: - 错误处理
enum LifelogError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "请先在设置中配置 Limitless AI API Key"
        case .invalidURL:
            return "无效的 API 地址"
        case .invalidResponse:
            return "服务器响应无效"
        case .apiError(let message):
            return "API 错误: \(message)"
        case .decodingError(let message):
            return "数据解析错误: \(message)"
        }
    }
}
