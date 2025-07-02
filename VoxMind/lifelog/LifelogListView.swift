import SwiftUI
import SwiftData

// MARK: - 日期状态管理扩展
extension ModelContext {
    /// 打印详细的错误信息
    private func logError(_ error: Error, operation: String) {
        print("❌ SwiftData错误 [\(operation)]:")
        print("  - 错误类型: \(type(of: error))")
        print("  - 错误描述: \(error.localizedDescription)")
        
        if let nsError = error as? NSError {
            print("  - 错误域: \(nsError.domain)")
            print("  - 错误代码: \(nsError.code)")
            if let details = nsError.userInfo["NSDetailedErrors"] as? [Error] {
                print("  - 详细错误:")
                details.forEach { detail in
                    print("    • \(detail)")
                }
            }
            if let reason = nsError.userInfo["NSUnderlyingError"] as? Error {
                print("  - 底层错误: \(reason)")
            }
            print("  - 完整信息: \(nsError)")
        }
    }
    
    /// 更新指定日期的加载状态
    /// - Parameters:
    ///   - dateKey: 日期键值（格式：YYYY-MM-DD）
    ///   - hasData: 是否有数据
    func updateDateLoadStatus(dateKey: String, hasData: Bool) {
        print("📊 updateDateLoadStatus: 更新日期 \(dateKey) 状态，hasData: \(hasData)")
        
        // 确保在主线程执行数据库操作
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.updateDateLoadStatus(dateKey: dateKey, hasData: hasData)
            }
            return
        }
        
        do {
            // 开始事务
            try transaction {
                // 先删除现有记录
                let descriptor = FetchDescriptor<DateLoadStatus>(
                    predicate: #Predicate<DateLoadStatus> { status in
                        status.dateKey == dateKey
                    }
                )
                
                let existingStatuses = try fetch(descriptor)
                print("📊 找到 \(existingStatuses.count) 个待删除的记录")
                for status in existingStatuses {
                    print("📊 删除记录: \(status.description)")
                    delete(status)
                }
                
                // 创建新记录
                let newStatus = DateLoadStatus(dateKey: dateKey, hasData: hasData)
                insert(newStatus)
                print("📊 插入新记录: \(newStatus.description)")
                
                // 立即保存上下文
                try save()
            }
            
            print("📊 ✅ 日期状态保存成功")
            
            // 验证保存结果
            let verifyDescriptor = FetchDescriptor<DateLoadStatus>(
                predicate: #Predicate<DateLoadStatus> { status in
                    status.dateKey == dateKey
                }
            )
            
            if let status = try fetch(verifyDescriptor).first {
                print("📊 验证 - 找到日期 \(dateKey) 的状态记录: \(status.description)")
            } else {
                print("❌ 验证 - 未找到日期 \(dateKey) 的状态记录")
                print("📊 尝试重新保存...")
                
                // 重试保存
                try transaction {
                    let newStatus = DateLoadStatus(dateKey: dateKey, hasData: hasData)
                    insert(newStatus)
                    print("📊 重试插入记录: \(newStatus.description)")
                    try save()
                }
                
                // 再次验证
                if let status = try fetch(verifyDescriptor).first {
                    print("📊 重试验证 - 找到日期 \(dateKey) 的状态记录: \(status.description)")
                } else {
                    print("❌ 重试验证 - 仍未找到日期 \(dateKey) 的状态记录")
                    
                    // 打印数据库状态
                    let allStatuses = try fetch(FetchDescriptor<DateLoadStatus>())
                    print("📊 数据库状态:")
                    print("  - 总记录数: \(allStatuses.count)")
                    for status in allStatuses {
                        print("  - \(status.description)")
                    }
                }
            }
        } catch {
            logError(error, operation: "更新日期状态")
        }
    }
    
    /// 加载所有日期状态
    /// - Returns: 包含有数据的日期集合和已加载的日期集合的元组
    func loadDateStatuses() -> (datesWithData: Set<String>, datesLoaded: Set<String>) {
        // 确保在主线程执行数据库查询
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                self.loadDateStatuses()
            }
        }
        
        do {
            let descriptor = FetchDescriptor<DateLoadStatus>()
            let statuses = try fetch(descriptor)
            print("📅 loadDateStatuses: 找到 \(statuses.count) 个日期状态记录")
            
            // 打印所有找到的记录
            for status in statuses {
                print("📅 状态记录: \(status.description)")
            }
            
            let datesWithData = Set(statuses.filter { $0.hasData }.map { $0.dateKey })
            let datesLoaded = Set(statuses.map { $0.dateKey })
            
            print("📅 有数据的日期: \(datesWithData.sorted())")
            print("📅 已加载的日期: \(datesLoaded.sorted())")
            
            return (datesWithData, datesLoaded)
        } catch {
            logError(error, operation: "加载日期状态")
            return (Set(), Set())
        }
    }
}

// MARK: - 日期加载状态模型
@Model
final class DateLoadStatus {
    // 使用复合主键
    @Attribute(.unique) var id: String // dateKey_timestamp
    var dateKey: String // YYYY-MM-DD
    var hasData: Bool
    var lastLoadedAt: Date
    
    init(dateKey: String, hasData: Bool) {
        self.dateKey = dateKey
        self.hasData = hasData
        self.lastLoadedAt = Date()
        // 创建一个唯一的ID，包含日期和时间戳
        self.id = "\(dateKey)_\(Int(Date().timeIntervalSince1970))"
    }
    
    // 用于调试的描述
    var description: String {
        return "DateLoadStatus(id: \(id), dateKey: \(dateKey), hasData: \(hasData), lastLoadedAt: \(lastLoadedAt))"
    }
}

// MARK: - 日期格式化工具
extension Date {
    func toDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

//挂件列表视图
struct LifeLogListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var lifelogs: [Lifelog] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    
    // 批量同步相关状态
    @State private var showBatchSync = false
    @State private var isBatchSyncing = false
    @State private var syncProgress: Double = 0.0
    @State private var syncStatusText = ""
    
    // 日历状态相关
    @State private var datesWithData: Set<String> = []
    @State private var datesLoaded: Set<String> = []
    
    private func dateKeyFromDate(_ date: Date) -> String {
        date.toDateKey()
    }
    
    private func loadDateStatuses() {
        Task { @MainActor in
            let (withData, loaded) = modelContext.loadDateStatuses()
            print("📅 更新日历状态 - 有数据的日期: \(withData.count)个, 已加载的日期: \(loaded.count)个")
            print("📅 有数据的日期: \(withData.sorted())")
            print("📅 已加载的日期: \(loaded.sorted())")
            datesWithData = withData
            datesLoaded = loaded
        }
    }
    
    // 按时间分组的生活日志
    private var groupedLifelogs: [TimeGroup] {
        let sortedLifelogs = lifelogs.sorted { lifelog1, lifelog2 in
            guard let time1 = lifelog1.startTime, let time2 = lifelog2.startTime else { return false }
            return time1 < time2
        }
        
        print("📊 总共 \(lifelogs.count) 条日志需要分组")
        
        var groups: [TimeGroup] = []
        var currentGroup: [Lifelog] = []
        var currentTimeSlot: String?
        
        for lifelog in sortedLifelogs {
            guard let startTime = lifelog.startTime else {
                print("⚠️ 跳过无时间的日志: \(lifelog.title)")
                continue
            }
            
            let timeSlot = getTimeSlotFromString(startTime)
            print("📅 日志 '\(lifelog.title)' 时间: \(startTime) -> 时间段: \(timeSlot)")
            
            if currentTimeSlot == nil {
                currentTimeSlot = timeSlot
                currentGroup = [lifelog]
            } else if currentTimeSlot == timeSlot {
                currentGroup.append(lifelog)
            } else {
                if !currentGroup.isEmpty {
                    let hour = hourFromTimeSlot(currentTimeSlot!)
                    groups.append(TimeGroup(hour: hour, lifelogs: currentGroup))
                    print("✅ 创建时间组: \(currentTimeSlot!) 包含 \(currentGroup.count) 条日志")
                }
                currentGroup = [lifelog]
                currentTimeSlot = timeSlot
            }
        }
        
        if !currentGroup.isEmpty, let timeSlot = currentTimeSlot {
            let hour = hourFromTimeSlot(timeSlot)
            groups.append(TimeGroup(hour: hour, lifelogs: currentGroup))
            print("✅ 创建最后一个时间组: \(timeSlot) 包含 \(currentGroup.count) 条日志")
        }
        
        print("🎯 最终创建了 \(groups.count) 个时间组")
        return groups
    }
    
    private func getTimeSlotFromString(_ timeString: String) -> String {
        // 尝试多种日期格式解析时间
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
        ]
        
        for formatString in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = formatString
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            if let date = formatter.date(from: timeString) {
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: date)
                let minute = calendar.component(.minute, from: date)
                
                // 按30分钟分组：如果分钟数 >= 30，则归入下半小时
                let timeSlot = minute >= 30 ? "\(hour):30" : "\(hour):00"
                return timeSlot
            }
        }
        
        print("⚠️ 时间解析失败: \(timeString)")
        return "00:00"
    }
    
    private func hourFromTimeSlot(_ timeSlot: String) -> Int {
        let components = timeSlot.split(separator: ":")
        if let hourString = components.first, let hour = Int(hourString) {
            return hour
        }
        return 0
    }
    
    private func hourFromTimeString(_ timeString: String) -> Int {
        let timeSlot = getTimeSlotFromString(timeString)
        return hourFromTimeSlot(timeSlot)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                
                HStack(spacing: 16) {
                    // 批量同步按钮（项链吊坠图标或同步图标）
                    Button(action: { showBatchSync = true }) {
                        ZStack {
                            // 基础图标
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 18))
                                .foregroundColor(isBatchSyncing ? .orange : .blue)
                            
                            // 进度圆环
                            if isBatchSyncing {
                                Circle()
                                    .trim(from: 0, to: syncProgress)
                                    .stroke(Color.orange, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 0.2), value: syncProgress)
                            }
                        }
                    }
                    .disabled(isBatchSyncing)
                    
                }
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
        .background(.regularMaterial)
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .sheet(isPresented: $showDatePicker) {
            NavigationView {
                VStack {
                    // 状态说明
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("有数据")
                                    .font(.caption)
                            }
                            HStack {
                                Circle()
                                    .fill(.gray)
                                    .frame(width: 8, height: 8)
                                Text("已加载，无数据")
                                    .font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // 自定义日历视图
                    CalendarDatePicker(
                        selectedDate: $selectedDate,
                        datesWithData: datesWithData,
                        datesLoaded: datesLoaded,
                        onDateSelected: { date in
                            selectedDate = date
                            showDatePicker = false
                            Task {
                                await refreshLifelogs()
                            }
                        }
                    )
                    .padding()
                    
                    Spacer()
                }
                .navigationTitle("选择日期")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("取消") {
                            showDatePicker = false
                        }
                    }
                }
#else
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("取消") {
                            showDatePicker = false
                        }
                    }
                }
#endif
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBatchSync) {
            BatchSyncView(
                isPresented: $showBatchSync,
                isSyncing: $isBatchSyncing,
                syncProgress: $syncProgress,
                syncStatusText: $syncStatusText,
                modelContext: modelContext,
                onSyncComplete: {
                    // 同步完成后刷新当前显示的数据和日历状态
                    loadDateStatuses()
                    refreshLifelogs()
                }
            )
        }
        .task {
            // 初始加载
            loadDateStatuses()
            await refreshLifelogs()
        }
        .onChange(of: selectedDate) { _ in
            Task {
                await refreshLifelogs()
            }
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
        
        let dateKey = dateKeyFromDate(selectedDate)
        let isToday = Calendar.current.isDateInToday(selectedDate)
        
        do {
            if isToday {
                // 当天数据：总是从远程获取最新数据，同时显示本地数据
                let (localLifelogs, remoteLifelogs) = try await loadTodayData(dateKey: dateKey)
                
                // 合并本地和远程数据，去重
                var combinedLifelogs = localLifelogs
                for remoteLog in remoteLifelogs {
                    if !combinedLifelogs.contains(where: { $0.id == remoteLog.id }) {
                        combinedLifelogs.append(remoteLog)
                    }
                }
                lifelogs = combinedLifelogs
                
                // 保存远程数据到本地
                await saveFetchedLifelogs(remoteLifelogs, dateKey: dateKey)
                
            } else {
                // 非当天数据：优先使用本地缓存
                let cachedLifelogs = loadCachedLifelogs(for: dateKey)
                
                if !cachedLifelogs.isEmpty {
                    // 使用缓存数据
                    lifelogs = cachedLifelogs
                } else {
                    // 缓存中没有数据，从远程获取
                    print("📅 加载日期 \(dateKey) 的数据")
                    let fetchedLifelogs = try await fetchLifelogs(for: selectedDate)
                    await MainActor.run {
                        self.lifelogs = fetchedLifelogs
                        modelContext.updateDateLoadStatus(dateKey: dateKey, hasData: !fetchedLifelogs.isEmpty)
                    }
                    
                    // 保存到本地缓存
                    await saveFetchedLifelogs(fetchedLifelogs, dateKey: dateKey)
                }
            }
            
        } catch {
            // 发生错误时，尝试从本地加载数据
            let cachedLifelogs = loadCachedLifelogs(for: dateKey)
            if !cachedLifelogs.isEmpty {
                lifelogs = cachedLifelogs
                errorMessage = "使用缓存数据，网络错误: \(error.localizedDescription)"
            } else {
                errorMessage = error.localizedDescription
            }
        }
        
        isLoading = false
        loadDateStatuses() // 更新日历状态
    }
    
    // MARK: - 缓存管理方法
    
    private func loadCachedLifelogs(for dateKey: String) -> [Lifelog] {
        let fetchDescriptor = FetchDescriptor<CachedLifelog>(
            predicate: #Predicate<CachedLifelog> { lifelog in
                lifelog.dateKey == dateKey
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        
        if let cachedLifelogs = try? modelContext.fetch(fetchDescriptor) {
            return cachedLifelogs.map { $0.toLifelog() }
        }
        
        return []
    }
    
    private func loadTodayData(dateKey: String) async throws -> ([Lifelog], [Lifelog]) {
        // 加载本地缓存数据
        let localLifelogs = loadCachedLifelogs(for: dateKey)
        
        // 获取远程数据
        let remoteLifelogs = try await fetchLifelogs(for: selectedDate)
        
        return (localLifelogs, remoteLifelogs)
    }
    
    @MainActor
    private func saveFetchedLifelogs(_ lifelogs: [Lifelog], dateKey: String) async {
        print("💾 saveFetchedLifelogs: 开始保存 \(lifelogs.count) 个lifelog到日期 \(dateKey)")
        
        var savedCount = 0
        var updatedCount = 0
        
        do {
            // 使用事务包装所有操作
            try modelContext.transaction {
                for lifelog in lifelogs {
                    // 检查是否已存在
                    let lifelogId = lifelog.id
                    let fetchDescriptor = FetchDescriptor<CachedLifelog>(
                        predicate: #Predicate<CachedLifelog> { cached in
                            cached.id == lifelogId
                        }
                    )
                    
                    if let existingCached = try modelContext.fetch(fetchDescriptor).first {
                        // 更新现有记录
                        existingCached.title = lifelog.title
                        existingCached.markdown = lifelog.markdown
                        existingCached.startTime = lifelog.startTime
                        existingCached.endTime = lifelog.endTime
                        existingCached.isStarred = lifelog.isStarred ?? false
                        existingCached.updatedAt = lifelog.updatedAt
                        existingCached.lastFetchedAt = Date()
                        
                        if let contents = lifelog.contents {
                            existingCached.contentNodes = try? JSONEncoder().encode(contents)
                        }
                        updatedCount += 1
                        print("💾 更新了存在的lifelog: \(lifelog.id)")
                    } else {
                        // 创建新记录
                        let cachedLifelog = CachedLifelog(from: lifelog, dateKey: dateKey)
                        modelContext.insert(cachedLifelog)
                        savedCount += 1
                        print("💾 插入了新的lifelog: \(lifelog.id)")
                    }
                }
            }
            
            print("💾 ✅ 成功保存上下文: 新增\(savedCount)个，更新\(updatedCount)个")
            
            // 等待一小段时间确保事务完成
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            
            // 更新日期状态
            modelContext.updateDateLoadStatus(dateKey: dateKey, hasData: !lifelogs.isEmpty)
            
            // 等待状态更新完成后再刷新状态
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            loadDateStatuses()
            
        } catch {
            print("❌ 保存上下文失败: \(error)")
        }
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
        return formatTimeToLocal(dateString)
    }
    
    private func formatTimeToLocal(_ dateString: String) -> String {
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
        ]
        
        // 解析 UTC 时间
        for formatString in formatters {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = formatString
            inputFormatter.locale = Locale(identifier: "en_US_POSIX")
            inputFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
            
            if let utcDate = inputFormatter.date(from: dateString) {
                // 转换为本地时区并格式化为 HH:mm
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "HH:mm"
                outputFormatter.timeZone = TimeZone.current // 本地时区
                
                return outputFormatter.string(from: utcDate)
            }
        }
        
        // 如果解析失败，返回原始字符串的简化版本
        if dateString.contains("T") {
            let components = dateString.split(separator: "T")
            if components.count > 1 {
                let timeComponent = String(components[1])
                let timeOnly = timeComponent.split(separator: ":").prefix(2).joined(separator: ":")
                return timeOnly
            }
        }
        
        return "00:00"
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
                        .foregroundColor(.primary)
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
            .background(.orange.opacity(0.1))
            .cornerRadius(8)
            
        case "paragraph":
            Text(node.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
        default:
            Text(node.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - SwiftData 模型
@Model
class CachedLifelog {
    @Attribute(.unique) var id: String
    var title: String
    var markdown: String?
    var startTime: String?
    var endTime: String?
    var isStarred: Bool
    var updatedAt: String?
    var dateKey: String // 用于按日期查询 (YYYY-MM-DD)
    var contentNodes: Data? // 序列化的 ContentNode 数组
    var createdAt: Date
    var lastFetchedAt: Date // 最后一次从服务器获取的时间
    
    init(from lifelog: Lifelog, dateKey: String) {
        self.id = lifelog.id
        self.title = lifelog.title
        self.markdown = lifelog.markdown
        self.startTime = lifelog.startTime
        self.endTime = lifelog.endTime
        self.isStarred = lifelog.isStarred ?? false
        self.updatedAt = lifelog.updatedAt
        self.dateKey = dateKey
        self.createdAt = Date()
        self.lastFetchedAt = Date()
        
        // 序列化 ContentNode 数组
        if let contents = lifelog.contents {
            self.contentNodes = try? JSONEncoder().encode(contents)
        }
    }
    
    func toLifelog() -> Lifelog {
        var contents: [ContentNode]? = nil
        if let contentNodes = self.contentNodes {
            contents = try? JSONDecoder().decode([ContentNode].self, from: contentNodes)
        }
        
        return Lifelog(
            id: id,
            title: title,
            markdown: markdown,
            contents: contents,
            startTime: startTime,
            endTime: endTime,
            isStarred: isStarred,
            updatedAt: updatedAt
        )
    }
}

// MARK: - API 响应数据模型
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

struct ContentNode: Codable, Hashable {
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
        // 如果该时间组有日志，尝试获取更精确的时间
        if let firstLog = lifelogs.first,
           let startTime = firstLog.startTime {
            
            // 尝试解析分钟信息
            let formatters = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm:ss",
            ]
            
            for formatString in formatters {
                let formatter = DateFormatter()
                formatter.dateFormat = formatString
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                
                if let date = formatter.date(from: startTime) {
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: date)
                    let minute = calendar.component(.minute, from: date)
                    return String(format: "%02d:%02d", hour, minute)
                }
            }
        }
        
        // 降级到小时显示
        return String(format: "%02d:00", hour)
    }
}

// MARK: - 时间轴组视图
struct TimelineGroupView: View {
    let timeGroup: TimeGroup
    let isFirst: Bool
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧时间轴 - 紧凑布局
            VStack(spacing: 0) {
                // 上方连接线
                if !isFirst {
                    Rectangle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 3, height: 20)
                }
                
                // 时间点和时间标签组合
                VStack(spacing: 4) {
                    // 时间点
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 14, height: 14)
                        
                        Circle()
                            .fill(.background)
                            .frame(width: 6, height: 6)
                    }
                    
                    // 紧凑的时间标签
                    Text(timeGroup.displayTime)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.12))
                        .cornerRadius(4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                
                // 下方连接线
                if !isLast {
                    Rectangle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 3)
                        .frame(minHeight: calculateMinHeight())
                }
            }
            .frame(width: 36)  // 减少宽度从 50 到 36
            
            // 右侧内容区域 - 占用更多空间
            VStack(alignment: .leading, spacing: 8) {
                ForEach(timeGroup.lifelogs, id: \.id) { lifelog in
                    TimelineLifelogCardView(lifelog: lifelog)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)  // 减少垂直间距
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
                    
                    HStack(spacing: 6) {
                        if let startTime = lifelog.startTime {
                            Text(formatTimeToLocal(startTime))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                        
                        if let endTime = lifelog.endTime {
                            Text("- \(formatTimeToLocal(endTime))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.blue)
                                .lineLimit(1)
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
                    
                    ForEach(filteredContents, id: \.hashValue) { content in
                        ContentNodeView(node: content, level: 0)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
    
    private func formatTime(_ dateString: String) -> String {
        return formatTimeToLocal(dateString)
    }
    
    private func formatTimeToLocal(_ dateString: String) -> String {
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
        ]
        
        // 解析 UTC 时间
        for formatString in formatters {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = formatString
            inputFormatter.locale = Locale(identifier: "en_US_POSIX")
            inputFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
            
            if let utcDate = inputFormatter.date(from: dateString) {
                // 转换为本地时区并格式化为 HH:mm
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "HH:mm"
                outputFormatter.timeZone = TimeZone.current // 本地时区
                
                return outputFormatter.string(from: utcDate)
            }
        }
        
        // 如果解析失败，返回原始字符串的简化版本
        if dateString.contains("T") {
            let components = dateString.split(separator: "T")
            if components.count > 1 {
                let timeComponent = String(components[1])
                let timeOnly = timeComponent.split(separator: ":").prefix(2).joined(separator: ":")
                return timeOnly
            }
        }
        
        return "00:00"
    }
}

// MARK: - 批量同步视图
struct BatchSyncView: View {
    @Binding var isPresented: Bool
    @Binding var isSyncing: Bool
    @Binding var syncProgress: Double
    @Binding var syncStatusText: String
    let modelContext: ModelContext
    let onSyncComplete: () -> Void
    
    @State private var selectedTimeRange: TimeRange = .lastWeek
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    
    private func dateKeyFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    enum TimeRange: String, CaseIterable {
        case lastWeek = "最近一周"
        case lastMonth = "最近一个月"
        case lastThreeMonths = "最近三个月"
        case custom = "自定义时间范围"
        
        func getDateRange() -> (Date, Date) {
            let calendar = Calendar.current
            let endDate = Date()
            
            switch self {
            case .lastWeek:
                let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate
                return (startDate, endDate)
            case .lastMonth:
                let startDate = calendar.date(byAdding: .month, value: -1, to: endDate) ?? endDate
                return (startDate, endDate)
            case .lastThreeMonths:
                let startDate = calendar.date(byAdding: .month, value: -3, to: endDate) ?? endDate
                return (startDate, endDate)
            case .custom:
                return (endDate, endDate) // 将在视图中使用自定义日期
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // 标题和描述
                VStack(spacing: 8) {
                    Text("批量同步数据")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("选择时间范围，批量同步 Limitless AI 的生活日志数据")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // 时间范围选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择时间范围")
                        .font(.headline)
                    
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        HStack {
                            Button(action: {
                                selectedTimeRange = range
                            }) {
                                HStack {
                                    Image(systemName: selectedTimeRange == range ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedTimeRange == range ? .blue : .gray)
                                    
                                    Text(range.rawValue)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // 自定义时间范围选择器
                    if selectedTimeRange == .custom {
                        VStack(spacing: 12) {
                            DatePicker("开始日期", selection: $customStartDate, displayedComponents: .date)
                            DatePicker("结束日期", selection: $customEndDate, displayedComponents: .date)
                        }
                        .padding(.leading, 32)
                    }
                }
                .padding(.horizontal)
                
                // 同步进度
                if isSyncing {
                    VStack(spacing: 12) {
                        ProgressView(value: syncProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        Text(syncStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(Int(syncProgress * 100))%")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // 操作按钮
                HStack(spacing: 16) {
                    Button("取消") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncing)
                    
                    Button("开始同步") {
                        startBatchSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSyncing)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("批量同步")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }
    
    private func startBatchSync() {
        Task {
            await performBatchSync()
        }
    }
    
    @MainActor
    private func performBatchSync() async {
        isSyncing = true
        syncProgress = 0.0
        syncStatusText = "准备同步..."
        
        // 获取时间范围
        let (startDate, endDate) = selectedTimeRange == .custom
        ? (customStartDate, customEndDate)
        : selectedTimeRange.getDateRange()
        
        // 生成日期列表
        var dates: [Date] = []
        var currentDate = startDate
        while currentDate <= endDate {
            dates.append(currentDate)
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        let totalDays = dates.count
        var completedDays = 0
        
        syncStatusText = "正在同步 \(totalDays) 天的数据..."
        
        // 逐日同步数据
        for date in dates {
            do {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dateString = dateFormatter.string(from: date)
                
                syncStatusText = "正在同步 \(dateString)..."
                
                // 调用 API 获取数据
                let lifelogs = try await fetchLifelogs(for: date)
                
                // 保存到 SwiftData
                await upsertLifelogs(lifelogs, for: date)
                
                completedDays += 1
                syncProgress = Double(completedDays) / Double(totalDays)
                
            } catch {
                print("同步日期 \(date) 失败: \(error)")
                // 继续同步其他日期
                completedDays += 1
                syncProgress = Double(completedDays) / Double(totalDays)
            }
        }
        
        syncStatusText = "同步完成！"
        
        // 延迟一下让用户看到完成状态
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        isSyncing = false
        onSyncComplete()
        isPresented = false
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
    
    @MainActor
    private func upsertLifelogs(_ lifelogs: [Lifelog], for date: Date) async {
        let dateKey = dateKeyFromDate(date)
        print("💾 开始保存 \(lifelogs.count) 个 lifelog 到日期 \(dateKey)")
        
        do {
            try modelContext.transaction {
                for lifelog in lifelogs {
                    // 检查是否已存在
                    let lifelogId = lifelog.id
                    let fetchDescriptor = FetchDescriptor<CachedLifelog>(
                        predicate: #Predicate<CachedLifelog> { cached in
                            cached.id == lifelogId
                        }
                    )
                    
                    if let existingCached = try? modelContext.fetch(fetchDescriptor).first {
                        // 更新现有记录（Upsert 操作）
                        print("💾 更新现有记录: \(lifelogId)")
                        existingCached.title = lifelog.title
                        existingCached.markdown = lifelog.markdown
                        existingCached.startTime = lifelog.startTime
                        existingCached.endTime = lifelog.endTime
                        existingCached.isStarred = lifelog.isStarred ?? false
                        existingCached.updatedAt = lifelog.updatedAt
                        existingCached.lastFetchedAt = Date()
                        
                        if let contents = lifelog.contents {
                            existingCached.contentNodes = try? JSONEncoder().encode(contents)
                        }
                    } else {
                        // 创建新记录
                        print("💾 创建新记录: \(lifelogId)")
                        let cachedLifelog = CachedLifelog(from: lifelog, dateKey: dateKey)
                        modelContext.insert(cachedLifelog)
                    }
                }
                
                // 立即保存上下文
                try modelContext.save()
            }
            
            // 验证保存结果
            let verifyDescriptor = FetchDescriptor<CachedLifelog>(
                predicate: #Predicate<CachedLifelog> { cached in
                    cached.dateKey == dateKey
                }
            )
            let savedLifelogs = try modelContext.fetch(verifyDescriptor)
            print("💾 验证结果: 找到 \(savedLifelogs.count) 个记录")
            
            // 更新日期状态
            modelContext.updateDateLoadStatus(dateKey: dateKey, hasData: !lifelogs.isEmpty)
            
        } catch {
            print("❌ 保存失败:")
            print("  - 错误类型: \(type(of: error))")
            print("  - 错误描述: \(error.localizedDescription)")
            
            if let nsError = error as? NSError {
                print("  - 错误域: \(nsError.domain)")
                print("  - 错误代码: \(nsError.code)")
                if let details = nsError.userInfo["NSDetailedErrors"] as? [Error] {
                    print("  - 详细错误:")
                    details.forEach { detail in
                        print("    • \(detail)")
                    }
                }
            }
        }
    }
}

// MARK: - 自定义日历选择器
struct CalendarDatePicker: View {
    @Binding var selectedDate: Date
    let datesWithData: Set<String>
    let datesLoaded: Set<String>
    let onDateSelected: (Date) -> Void
    
    @State private var displayedMonth = Date()
    
    var body: some View {
        VStack {
            // 月份导航
            HStack {
                Button(action: {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    print("📅 切换到上个月: \(monthYearString(displayedMonth))")
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(monthYearString(displayedMonth))
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    print("📅 切换到下个月: \(monthYearString(displayedMonth))")
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            // 周几标题
            HStack {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // 日期网格
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(daysInMonth(), id: \.id) { dayInfo in
                    if let date = dayInfo.date {
                        CalendarDayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            isToday: Calendar.current.isDateInToday(date),
                            hasData: datesWithData.contains(date.toDateKey()),
                            wasLoaded: datesLoaded.contains(date.toDateKey())
                        ) {
                            onDateSelected(date)
                        }
                    } else {
                        Text("")
                            .frame(height: 40)
                            .id(dayInfo.id) // 为空白单元格添加唯一ID
                    }
                }
            }
            .padding(.horizontal)
        }
        .onChange(of: displayedMonth) { _ in
            print("📅 月份变更 - 当前有数据的日期: \(datesWithData.sorted())")
            print("📅 月份变更 - 当前已加载的日期: \(datesLoaded.sorted())")
        }
    }
    
    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }
    
    private struct DayInfo: Identifiable {
        let id: String // 使用字符串作为ID，确保唯一性
        let date: Date?
        
        init(date: Date?, offset: Int) {
            self.date = date
            if let date = date {
                self.id = "day_\(date.toDateKey())"
            } else {
                self.id = "empty_\(offset)" // 为空白日期生成唯一ID
            }
        }
    }
    
    private func daysInMonth() -> [DayInfo] {
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let range = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let offsetDays = (firstWeekday + 5) % 7 // 调整为周一开始
        
        // 创建空白日期
        var days: [DayInfo] = (0..<offsetDays).map { offset in
            DayInfo(date: nil, offset: offset)
        }
        
        // 添加月份中的日期
        for day in 1...range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(DayInfo(date: date, offset: offsetDays + day))
            }
        }
        
        return days
    }
}

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasData: Bool
    let wasLoaded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 背景圆圈
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)
                
                // 日期数字
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundColor(textColor)
                
                // 数据状态指示器
                if hasData || wasLoaded {
                    VStack {
                        Spacer()
                        Circle()
                            .fill(hasData ? .green : .gray)
                            .frame(width: 6, height: 6)
                            .padding(.bottom, 2)
                    }
                    .frame(width: 36, height: 36)
                }
            }
        }
        .frame(height: 40)
        .onChange(of: hasData) { newHasData in
            print("📅 日期单元格状态更新 - 日期: \(date.toDateKey()), hasData: \(newHasData), wasLoaded: \(wasLoaded)")
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue.opacity(0.2)
        } else {
            return .clear
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .blue
        } else {
            return .primary
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
