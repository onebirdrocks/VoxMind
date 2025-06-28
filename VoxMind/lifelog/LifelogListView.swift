import SwiftUI

//挂件列表视图
struct LifeLogListView: View {
    @State private var lifelogs: [Lifelog] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    
    // 按时间分组的生活日志
    private var groupedLifelogs: [TimeGroup] {
        let sortedLifelogs = lifelogs.sorted { lifelog1, lifelog2 in
            guard let time1 = lifelog1.startTime, let time2 = lifelog2.startTime else { return false }
            return time1 < time2
        }
        
        var groups: [TimeGroup] = []
        var currentGroup: [Lifelog] = []
        var currentHour: Int?
        
        for lifelog in sortedLifelogs {
            guard let startTime = lifelog.startTime else { continue }
            let hour = hourFromTimeString(startTime)
            
            if currentHour == nil {
                currentHour = hour
                currentGroup = [lifelog]
            } else if currentHour == hour {
                currentGroup.append(lifelog)
            } else {
                if !currentGroup.isEmpty {
                    groups.append(TimeGroup(hour: currentHour!, lifelogs: currentGroup))
                }
                currentGroup = [lifelog]
                currentHour = hour
            }
        }
        
        if !currentGroup.isEmpty, let hour = currentHour {
            groups.append(TimeGroup(hour: hour, lifelogs: currentGroup))
        }
        
        return groups
    }
    
    private func hourFromTimeString(_ timeString: String) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        if let date = formatter.date(from: timeString) {
            let calendar = Calendar.current
            return calendar.component(.hour, from: date)
        }
        return 0
    }
    
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
                    // 生活日志列表 - 时间轴视图
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(groupedLifelogs.enumerated()), id: \.offset) { index, timeGroup in
                                TimelineGroupView(
                                    timeGroup: timeGroup,
                                    isFirst: index == 0,
                                    isLast: index == groupedLifelogs.count - 1
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .refreshable {
                        await refreshLifelogsAsync()
                    }
                }
            }
            .background(.gray.opacity(0.1))
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
            Image(systemName: "doc.text.fill")
                .foregroundColor(.blue)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
                
        case "heading2":
            if hasChildren {
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .medium))
                }
            } else {
                Image(systemName: "2.square.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
            }
                
        case "heading3":
            if hasChildren {
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .medium))
                }
            } else {
                Image(systemName: "3.square.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
            }
                
        case "blockquote":
            Image(systemName: "quote.bubble.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
                
        case "paragraph":
            Image(systemName: "text.alignleft")
                .foregroundColor(.gray.opacity(0.7))
                .font(.system(size: 13, weight: .regular))
                .frame(width: 20)
                
        default:
            Image(systemName: "circle.fill")
                .foregroundColor(.gray.opacity(0.5))
                .font(.system(size: 10))
                .frame(width: 20)
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
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
            
        case "heading2":
            Text(node.content)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 1)
            
        case "heading3":
            Text(node.content)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 1)
            
        case "blockquote":
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 4)
                    .cornerRadius(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black.opacity(0.8))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let speaker = node.speakerName, !speaker.isEmpty {
                        Text("— \(speaker)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.all, 10)
            .background(.orange.opacity(0.05))
            .cornerRadius(8)
            
        case "paragraph":
            Text(node.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.black.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
        default:
            Text(node.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.black.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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

// MARK: - 时间分组数据结构
struct TimeGroup {
    let hour: Int
    let lifelogs: [Lifelog]
    
    var timeRange: String {
        let endHour = hour + 1
        return String(format: "%02d:00", hour)
    }
    
    var displayTime: String {
        return String(format: "%02d:00", hour)
    }
}

// MARK: - 时间轴组视图
struct TimelineGroupView: View {
    let timeGroup: TimeGroup
    let isFirst: Bool
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // 左侧时间轴
            VStack(spacing: 0) {
                // 上方连接线
                if !isFirst {
                    Rectangle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 3, height: 24)
                }
                
                // 时间点和时间标签
                VStack(spacing: 6) {
                    // 时间点
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                    }
                    
                    // 时间标签
                    Text(timeGroup.displayTime)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.15))
                        .cornerRadius(8)
                }
                
                // 下方连接线
                if !isLast {
                    Rectangle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 3)
                        .frame(minHeight: calculateMinHeight())
                }
            }
            .frame(width: 50)
            
            // 右侧内容区域
            VStack(alignment: .leading, spacing: 10) {
                ForEach(timeGroup.lifelogs, id: \.id) { lifelog in
                    TimelineLifelogCardView(lifelog: lifelog)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }
    
    private func calculateMinHeight() -> CGFloat {
        // 根据该时间段的日志数量动态计算连接线高度
        let baseHeight: CGFloat = 80
        let additionalHeight: CGFloat = CGFloat(max(0, timeGroup.lifelogs.count - 1)) * 60
        return baseHeight + additionalHeight
    }
}

// MARK: - 时间轴日志卡片视图
struct TimelineLifelogCardView: View {
    let lifelog: Lifelog
    @State private var isExpanded = false
    
    // 过滤掉第一个 heading1（避免与标题重复）
    private var filteredContents: [ContentNode] {
        guard let contents = lifelog.contents, !contents.isEmpty else { return [] }
        
        // 如果第一个节点是 heading1 且内容与标题相同，则跳过它
        if contents.first?.type == "heading1" && contents.first?.content == lifelog.title {
            return Array(contents.dropFirst())
        }
        
        return contents
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题栏
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(lifelog.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        if let startTime = lifelog.startTime {
                            Text(formatTime(startTime))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        if let endTime = lifelog.endTime {
                            Text("- \(formatTime(endTime))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        if lifelog.isStarred == true {
                            Image(systemName: "star.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                        }
                    }
                }
                
                Spacer()
                
                if !filteredContents.isEmpty {
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // 内容区域（可展开）
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(.gray.opacity(0.3))
                    
                    ForEach(filteredContents, id: \.hashValue) { content in
                        ContentNodeView(node: content, level: 0)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.gray.opacity(0.15), lineWidth: 0.5)
        )
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
