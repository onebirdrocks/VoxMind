//
//  ContentView.swift
//  OBVoiceLab
//
//  Created by Ruan Yiming on 2025/6/22.
//
import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation

import Translation

// 主题管理类
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .system
    
    enum AppTheme: String, CaseIterable {
        case light = "light"
        case dark = "dark"
        case system = "system"
        
        var displayName: String {
            switch self {
            case .light: return "白天"
            case .dark: return "黑夜"
            case .system: return "系统"
            }
        }
        
        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }
    
    init() {
        // 从 UserDefaults 加载保存的主题设置
        if let savedTheme = UserDefaults.standard.string(forKey: "AppTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.currentTheme = theme
        }
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "AppTheme")
    }
}

// API 管理类
class APIManager: ObservableObject {
    @Published var selectedProvider: LLMProvider = .openai
    @Published var selectedModel: LLMModel = LLMModel(id: "gpt-4o", displayName: "GPT-4o")
    @Published var apiKeys: [String: String] = [:]
    @Published var isValidating: Bool = false
    @Published var validationStatus: ValidationStatus = .none
    
    // 存储每个提供商的验证状态

    
    enum ValidationStatus {
        case none
        case valid
        case invalid(String)
        
        var message: String {
            switch self {
            case .none: return ""
            case .valid: return "API Key 验证成功"
            case .invalid(let error): return "验证失败: \(error)"
            }
        }
        
        var color: Color {
            switch self {
            case .none: return .primary
            case .valid: return .green
            case .invalid: return .red
            }
        }
    }
    

    
    init() {
        // 从 UserDefaults 加载保存的设置
        let defaultProvider = LLMConfig.defaultProvider()
        self.selectedProvider = defaultProvider
        self.selectedModel = LLMConfig.defaultModel(for: defaultProvider)
        
        // 加载所有Provider的API Keys
        for provider in LLMProvider.allCases {
            let key = UserDefaults.standard.string(forKey: provider.rawValue + "APIKey") ?? ""
            apiKeys[provider.rawValue] = key
        }
        
    }
    
    func validateAndSaveAPIKey() async {
        await MainActor.run {
            isValidating = true
            validationStatus = .none
        }
        
        let currentAPIKey = apiKeys[selectedProvider.rawValue] ?? ""
        guard !currentAPIKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                isValidating = false
                validationStatus = .invalid("API Key 不能为空")
            }
            return
        }
        
        print("🆕 执行验证 for \(selectedProvider.displayName)")
        
        do {
            let isValid = try await validateAPIKey(currentAPIKey, for: selectedProvider)
            await MainActor.run {
                if isValid {
                    UserDefaults.standard.set(currentAPIKey, forKey: selectedProvider.rawValue + "APIKey")
                    validationStatus = .valid
                } else {
                    validationStatus = .invalid("API Key 无效")
                }
                isValidating = false
            }
        } catch {
            await MainActor.run {
                let errorMessage = error.localizedDescription
                validationStatus = .invalid(errorMessage)
                isValidating = false
            }
        }
    }
    
    private func validateAPIKey(_ apiKey: String, for provider: LLMProvider) async throws -> Bool {
        print("🔍 开始验证 \(provider.displayName) API Key...")
        print("🔑 Key 长度: \(apiKey.count)")
        print("🔑 Key 前缀: \(String(apiKey.prefix(10)))...")
        
        // 针对不同提供商使用不同的验证方式
        let endpoint: String
        
        switch provider.rawValue {
        case "openrouter":
            endpoint = "/models"  // OpenRouter 使用 models 端点验证
        case "aliyun":
            endpoint = "/models"  // 阿里云通义千问使用 models 端点
        default:
            endpoint = "/models"  // 默认使用 models 端点
        }
        
        guard let url = URL(string: "\(provider.baseURL)\(endpoint)") else {
            print("❌ 无效的验证 URL: \(provider.baseURL)\(endpoint)")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 根据不同提供商设置认证方式
        switch provider.rawValue {
        case "aliyun":
            // 阿里云使用 Authorization: Bearer API_KEY
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case "openrouter":
            // OpenRouter 使用标准 Bearer 认证加特殊头部
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("https://voxmind.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("VoxMind", forHTTPHeaderField: "X-Title")
            request.setValue("VoxMind/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        default:
            // 其他提供商使用标准 Bearer 认证
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        print("📤 验证请求发送到: \(url)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 验证响应状态码: \(httpResponse.statusCode)")
                
                // 打印响应内容以便调试
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 验证响应内容: \(String(responseString.prefix(500)))...")
                }
                
                // 根据不同提供商判断成功状态
                switch provider.rawValue {
                case "openrouter":
                    if httpResponse.statusCode == 200 {
                        // 检查响应是否包含模型列表
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let dataArray = json["data"] as? [[String: Any]],
                           !dataArray.isEmpty {
                            print("✅ OpenRouter 验证成功，找到 \(dataArray.count) 个模型")
                            return true
                        } else {
                            print("⚠️ OpenRouter 返回 200 但没有模型数据")
                            return false
                        }
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ OpenRouter API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ OpenRouter 验证失败，状态码: \(httpResponse.statusCode)")
                        return false
                    }
                    
                case "aliyun":
                    if httpResponse.statusCode == 200 {
                        print("✅ 阿里云通义千问验证成功")
                        return true
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ 阿里云 API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ 阿里云验证失败，状态码: \(httpResponse.statusCode)")
                        return false
                    }
                    
                case "deepseek":
                    if httpResponse.statusCode == 200 {
                        print("✅ DeepSeek 验证成功")
                        return true
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ DeepSeek API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ DeepSeek 验证失败，状态码: \(httpResponse.statusCode)")
                        return false
                    }
                    
                default:
                    // 其他提供商的通用验证
                    if httpResponse.statusCode == 200 {
                        print("✅ \(provider.displayName) 验证成功")
                        return true
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ \(provider.displayName) API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ \(provider.displayName) 验证失败，状态码: \(httpResponse.statusCode)")
                        return false
                    }
                }
            }
            
            print("❌ 无法获取 HTTP 响应")
            return false
            
        } catch {
            print("❌ 验证请求失败: \(error.localizedDescription)")
            
            // 网络错误可能不代表 API Key 无效
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                    throw APIError.apiError("网络连接问题，请检查网络设置")
                default:
                    throw APIError.apiError("网络请求失败: \(urlError.localizedDescription)")
                }
            }
            
            throw error
        }
    }
    
    func setProvider(_ provider: LLMProvider) {
        selectedProvider = provider
        // 确保selectedModel是新Provider支持的模型
        let newDefaultModel = LLMConfig.defaultModel(for: provider)
        selectedModel = newDefaultModel
        LLMConfig.saveSelectedProvider(provider)
        LLMConfig.saveSelectedModel(newDefaultModel, for: provider)
        validationStatus = .none
    }
    
    func setModel(_ model: LLMModel) {
        selectedModel = model
        LLMConfig.saveSelectedModel(model, for: selectedProvider)
    }
    
    func updateAPIKey(_ key: String, for provider: LLMProvider) {
        apiKeys[provider.rawValue] = key
        validationStatus = .none
    }
    

}


extension View {
    func hideKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// 设置视图
struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var apiManager: APIManager
    @State private var limitlessAPIKey: String = UserDefaults.standard.string(forKey: "LimitlessAIAPIKey") ?? ""
    @State private var limitlessSaveStatus: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal])
            Form {
                Section("主题设置") {
                    Picker("主题模式", selection: $themeManager.currentTheme) {
                        ForEach(ThemeManager.AppTheme.allCases, id: \.self) { theme in
                            Image(systemName: iconForTheme(theme))
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: themeManager.currentTheme) { _, newTheme in
                        themeManager.setTheme(newTheme)
                    }
                }
                
                Section("LLM 提供商设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Provider 选择
                        Picker("LLM 提供商", selection: $apiManager.selectedProvider) {
                            ForEach(LLMProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: apiManager.selectedProvider) { _, newProvider in
                            apiManager.setProvider(newProvider)
                        }
                        
                        // Model 选择
                        Picker("模型", selection: $apiManager.selectedModel) {
                            ForEach(apiManager.selectedProvider.supportedModels, id: \.id) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: apiManager.selectedModel) { _, newModel in
                            apiManager.setModel(newModel)
                        }
                        .id(apiManager.selectedProvider.id)
                        
                        // API Key 输入
                        let currentAPIKey = Binding<String>(
                            get: { apiManager.apiKeys[apiManager.selectedProvider.rawValue] ?? "" },
                            set: { apiManager.updateAPIKey($0, for: apiManager.selectedProvider) }
                        )
                        
                        SecureField("请输入 \(apiManager.selectedProvider.displayName) API Key", text: currentAPIKey)
                            .textFieldStyle(.roundedBorder)
                        

                        
                        // 显示当前验证状态
                        if case .none = apiManager.validationStatus {
                            // 不显示任何状态
                        } else {
                            Text(apiManager.validationStatus.message)
                                .font(.caption)
                                .foregroundColor(apiManager.validationStatus.color)
                        }
                        
                        Button {
                            Task {
                                await apiManager.validateAndSaveAPIKey()
                            }
                        } label: {
                            HStack {
                                if apiManager.isValidating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                
                                Text(getValidationButtonText())
                            }
                        }
                        .disabled(apiManager.isValidating || (apiManager.apiKeys[apiManager.selectedProvider.rawValue] ?? "").isEmpty)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                    .padding(.vertical, 4)
                }
                // 新增 Limitless.AI 设置
                Section("挂件 Limitless.AI 设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("请输入 Limitless.AI API Key", text: $limitlessAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Button("保存") {
                            UserDefaults.standard.set(limitlessAPIKey, forKey: "LimitlessAIAPIKey")
                            limitlessSaveStatus = "已保存"
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        if !limitlessSaveStatus.isEmpty {
                            Text(limitlessSaveStatus)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .hideKeyboardOnTap()
        }
    }
    
    private func iconForTheme(_ theme: ThemeManager.AppTheme) -> String {
        switch theme {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "gear"
        }
    }
    
    private func getValidationButtonText() -> String {
        return apiManager.isValidating ? "验证中..." : "验证并保存"
    }
}

// 本机视图（原VoiceLog列表）
struct LocalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceLog.title) private var stories: [VoiceLog]
    @State private var selection: VoiceLog?
    @State private var showingDeleteAlert = false
    @State private var storyToDelete: VoiceLog?
    @ObservedObject var apiManager: APIManager
    @Binding var searchText: String
    @Binding var isSearching: Bool
    
    private var filteredStories: [VoiceLog] {
        if searchText.isEmpty {
            return stories
        } else {
            return stories.filter { story in
                story.title.localizedCaseInsensitiveContains(searchText) ||
                String(story.text.characters).localizedCaseInsensitiveContains(searchText) ||
                (story.originalSummary?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (story.chineseSummary?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    // 停止所有音频播放的方法
    private func stopAllAudioPlayback() {
        NotificationCenter.default.post(name: NSNotification.Name("stopAllPlayback"), object: nil)
    }
    
    // 删除单个Story的方法
    private func deleteStory(_ story: VoiceLog) {
        withAnimation {
            if selection?.id == story.id {
                selection = nil
            }
            
            if let audioURL = story.url,
               FileManager.default.fileExists(atPath: audioURL.path) {
                try? FileManager.default.removeItem(at: audioURL)
                print("Deleted audio file: \(audioURL.lastPathComponent)")
            }
            
            modelContext.delete(story)
            print("Deleted story: \(story.title)")
            
            do {
                try modelContext.save()
                print("Successfully saved context after deletion")
            } catch {
                print("Failed to save context after deletion: \(error)")
            }
        }
        
        storyToDelete = nil as VoiceLog?
    }
    
    // 删除Story记录的方法（批量删除）
    private func deleteStories(offsets: IndexSet) {
        withAnimation {
            let storiesToDelete = filteredStories
            for index in offsets {
                let story = storiesToDelete[index]
                deleteStory(story)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filteredStories) { story in
                    NavigationLink(value: story) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(story.title)
                                .font(.headline)
                            if story.isDone {
                                Text("已录制并翻译")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("录制中...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        Button {
                            storyToDelete = story
                            showingDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .foregroundColor(.red)
                    }
                }
                .onDelete(perform: deleteStories)
            }
            .navigationTitle("本机")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        stopAllAudioPlayback()
                        
                        let newStory = VoiceLog.blank()
                        modelContext.insert(newStory)
                        
                        DispatchQueue.main.async {
                            selection = newStory
                        }
                        
                        print("Created new story: \(newStory.title), isDone: \(newStory.isDone)")
                        print("Selection set to new story: \(newStory.id)")
                    } label: {
                        Label("新建录音", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selectedStory = selection {
                VoiceLogDetailView(story: selectedStory, apiManager: apiManager)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("🎙️ 欢迎使用 VoxMind!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("我将帮助您轻松录制、转录 ✍️、翻译 🌐 和总结 📝 您的语音日志")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let story = storyToDelete {
                    deleteStory(story)
                }
            }
        } message: {
            if let story = storyToDelete {
                Text("确定要删除语音日志「\(story.title)」吗？此操作无法撤销。")
            }
        }
    }
}

// 挂件视图
struct WidgetView: View {
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

// 录音视图
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var apiManager: APIManager
    
    // 回调函数，用于通知父视图启动全屏录音
    let onStartRecording: (VoiceLog, VoiceLogDetailView.LanguageOption, VoiceLogDetailView.LanguageOption) -> Void
    
    @State private var selectedInputLanguage: VoiceLogDetailView.LanguageOption = {
        if let savedInput = UserDefaults.standard.string(forKey: "SelectedInputLanguage"),
           let language = VoiceLogDetailView.LanguageOption.allCases.first(where: { $0.rawValue == savedInput }) {
            return language
        }
        return .english
    }()
    @State private var selectedTargetLanguage: VoiceLogDetailView.LanguageOption = {
        if let savedTarget = UserDefaults.standard.string(forKey: "SelectedTargetLanguage"),
           let language = VoiceLogDetailView.LanguageOption.allCases.first(where: { $0.rawValue == savedTarget }) {
            return language
        }
        return .chinese
    }()
    @State private var supportedLanguages: Set<String> = []
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    
    init(apiManager: APIManager, onStartRecording: @escaping (VoiceLog, VoiceLogDetailView.LanguageOption, VoiceLogDetailView.LanguageOption) -> Void) {
        self.apiManager = apiManager
        self.onStartRecording = onStartRecording
    }
    
    // 页面加载时拉取支持的语言
    private func loadSupportedLanguages() {
        Task {
            let transcriber = SpokenWordTranscriber(story: .constant(VoiceLog.blank()))
            let supported = await transcriber.getSupportedLocales()
            await MainActor.run {
                supportedLanguages = supported
            }
        }
    }
    
    // 验证语言选择
    private func validateLanguageSelection() -> Bool {
        // 检查说话语言是否支持
        if !supportedLanguages.isEmpty && !supportedLanguages.contains(selectedInputLanguage.rawValue) {
            validationMessage = "选择的说话语言 \(selectedInputLanguage.displayName) 不受支持。请选择其他语言。"
            return false
        }
        
        // 检查说话语言和翻译语言是否相同
        if selectedInputLanguage == selectedTargetLanguage {
            validationMessage = "说话语言和翻译语言不能相同。请选择不同的语言。"
            return false
        }
        
        return true
    }
    
    // 保存用户的语言选择
    private func saveLanguageSelection() {
        UserDefaults.standard.set(selectedInputLanguage.rawValue, forKey: "SelectedInputLanguage")
        UserDefaults.standard.set(selectedTargetLanguage.rawValue, forKey: "SelectedTargetLanguage")
        print("✅ 已保存语言选择: \(selectedInputLanguage.displayName) → \(selectedTargetLanguage.displayName)")
    }
    
    private struct LanguageSettingsView: View {
        @Binding var selectedInputLanguage: VoiceLogDetailView.LanguageOption
        @Binding var selectedTargetLanguage: VoiceLogDetailView.LanguageOption
        var supportedLanguages: Set<String>
        
        private func languageMenuItem(lang: VoiceLogDetailView.LanguageOption, selected: VoiceLogDetailView.LanguageOption, supported: Bool) -> some View {
            HStack {
                Text(lang.flag)
                Text(lang.displayName)
                if lang == selected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
                if !supported {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("不支持")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .font(.caption2)
            .foregroundColor(supported ? .primary : .secondary)
        }
        
        private func languageMenuItemTarget(lang: VoiceLogDetailView.LanguageOption, selected: VoiceLogDetailView.LanguageOption) -> some View {
            HStack {
                Text(lang.flag)
                Text(lang.displayName)
                if lang == selected {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
            .font(.caption2)
        }
        
        private func languageMenuLabel(lang: VoiceLogDetailView.LanguageOption) -> some View {
            HStack(spacing: 4) {
                Text(lang.flag)
                    .font(.callout)
                Text(lang.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        
        var body: some View {
            VStack(spacing: 24) {
                Text("语言设置")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        // 说话语言选择
                        VStack(alignment: .leading, spacing: 4) {
                            Text("说话语言")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Menu {
                                ForEach(VoiceLogDetailView.LanguageOption.allCases) { lang in
                                    let supported = supportedLanguages.isEmpty || supportedLanguages.contains(lang.rawValue)
                                    Button {
                                        selectedInputLanguage = lang
                                        // 实时保存选择
                                        UserDefaults.standard.set(lang.rawValue, forKey: "SelectedInputLanguage")
                                    } label: {
                                        languageMenuItem(lang: lang, selected: selectedInputLanguage, supported: supported)
                                    }
                                    .disabled(!supported)
                                }
                            } label: {
                                languageMenuLabel(lang: selectedInputLanguage)
                            }
                        }
                        
                        // 箭头
                        Image(systemName: "arrow.right")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                            .frame(width: 24)
                        
                        // 翻译语言选择
                        VStack(alignment: .leading, spacing: 4) {
                            Text("翻译语言")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Menu {
                                ForEach(VoiceLogDetailView.LanguageOption.allCases) { lang in
                                    Button {
                                        selectedTargetLanguage = lang
                                        // 实时保存选择
                                        UserDefaults.standard.set(lang.rawValue, forKey: "SelectedTargetLanguage")
                                    } label: {
                                        languageMenuItemTarget(lang: lang, selected: selectedTargetLanguage)
                                    }
                                }
                            } label: {
                                languageMenuLabel(lang: selectedTargetLanguage)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.1)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            )
            .padding(.horizontal, 24)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {

                    VStack(spacing: 30) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.red)
                        
                        Text("开始新的录音")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("点击下方按钮开始录制您的语音")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            if validateLanguageSelection() {
                                saveLanguageSelection()
                                let newStory = VoiceLog.blank()
                                modelContext.insert(newStory)
                                onStartRecording(newStory, selectedInputLanguage, selectedTargetLanguage)
                                print("Created new story for recording: \(newStory.title)")
                                print("Selected languages: \(selectedInputLanguage.displayName) → \(selectedTargetLanguage.displayName)")
                            } else {
                                showValidationAlert = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "mic.fill")
                                Text("开始录音")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(Color.red)
                            .cornerRadius(25)
                        }
                        // 语言设置区域（加圆角背景和阴影）
                        LanguageSettingsView(selectedInputLanguage: $selectedInputLanguage, selectedTargetLanguage: $selectedTargetLanguage, supportedLanguages: supportedLanguages)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                    .onAppear {
                        loadSupportedLanguages()
                    }
            }
            .alert("语言设置错误", isPresented: $showValidationAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }
}

// 搜索视图
struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceLog.title) private var stories: [VoiceLog]
    @State private var selection: VoiceLog?
    @ObservedObject var apiManager: APIManager
    @Binding var searchText: String
    
    private var filteredStories: [VoiceLog] {
        if searchText.isEmpty {
            return []
        } else {
            return stories.filter { story in
                story.title.localizedCaseInsensitiveContains(searchText) ||
                String(story.text.characters).localizedCaseInsensitiveContains(searchText) ||
                (story.originalSummary?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (story.chineseSummary?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            VStack {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("搜索语音日志...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top)
                
                // 搜索结果
                if searchText.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        
                        Text("搜索语音日志")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("输入关键词来搜索您的语音日志")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else if filteredStories.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        
                        Text("未找到结果")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("没有找到包含\"\(searchText)\"的语音日志")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List(selection: $selection) {
                        ForEach(filteredStories) { story in
                            NavigationLink(value: story) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(story.title)
                                        .font(.headline)
                                    if story.isDone {
                                        Text("已录制并翻译")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("录制中...")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    // 显示匹配的内容片段
                                    let textContent = String(story.text.characters)
                                    if !textContent.isEmpty && textContent.localizedCaseInsensitiveContains(searchText) {
                                        Text(textContent.prefix(100) + (textContent.count > 100 ? "..." : ""))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("搜索")
        } detail: {
            if let selectedStory = selection {
                VoiceLogDetailView(story: selectedStory, apiManager: apiManager)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("选择搜索结果")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("从左侧列表中选择一个语音日志来查看详情")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }
}

// 全屏录音视图
struct FullScreenRecordingView: View {
    @Bindable var story: VoiceLog
    @ObservedObject var apiManager: APIManager
    @EnvironmentObject var themeManager: ThemeManager
    let sourceLanguage: VoiceLogDetailView.LanguageOption
    let targetLanguage: VoiceLogDetailView.LanguageOption
    let onDismiss: (VoiceLog?) -> Void
    
    @State private var recorder: Recorder!
    @State private var speechTranscriber: SpokenWordTranscriber!
    @State private var isRecording = false
    @State private var isStoppingRecording = false
    @State private var stopCountdown = 0
    @State private var isGeneratingTitleAndSummary = false
    @State private var translationSession: TranslationSession?
    
    var body: some View {
        ZStack {
            // 背景 - 根据主题使用不同的颜色
            (themeManager.currentTheme == .dark ? Color.black : Color(.systemBackground))
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // 语言显示 - 移到顶部，更紧凑
                VStack(spacing: 4) {
                    Text("录音中...")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.8) : .primary.opacity(0.8))
                    
                    HStack(spacing: 6) {
                        VStack(spacing: 1) {
                            Text(sourceLanguage.flag)
                                .font(.caption2)
                            Text(sourceLanguage.displayName)
                                .font(.caption2)
                                .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.7) : .primary.opacity(0.7))
                        }
                        
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.5) : .primary.opacity(0.5))
                        
                        VStack(spacing: 1) {
                            Text(targetLanguage.flag)
                                .font(.caption2)
                            Text(targetLanguage.displayName)
                                .font(.caption2)
                                .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.7) : .primary.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 50)
                
                // 转录文本显示区域 - 更大，自动滚动，适配主题
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let finalizedTranscript = speechTranscriber?.finalizedTranscript, !finalizedTranscript.characters.isEmpty {
                                Text(finalizedTranscript)
                                    .foregroundStyle(themeManager.currentTheme == .dark ? .white : .primary)
                                    .font(.body)
                                    .id("finalizedText")
                            }
                            
                            if let volatileTranscript = speechTranscriber?.volatileTranscript, !volatileTranscript.characters.isEmpty {
                                Text(volatileTranscript)
                                    .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.6) : .primary.opacity(0.6))
                                    .font(.body)
                                    .id("volatileText")
                            } else if speechTranscriber?.finalizedTranscript.characters.isEmpty ?? true {
                                Text("语音转录将在这里显示...")
                                    .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.5) : .primary.opacity(0.5))
                                    .font(.body)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .onChange(of: speechTranscriber?.finalizedTranscript) { _, _ in
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("finalizedText", anchor: .bottom)
                            }
                        }
                        .onChange(of: speechTranscriber?.volatileTranscript) { _, _ in
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("volatileText", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: 350)
                .background(themeManager.currentTheme == .dark ? Color.white.opacity(0.1) : Color.primary.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // 翻译文本显示区域 - 更大，自动滚动，适配主题，始终显示
                ScrollViewReader { proxy in
                    ScrollView {
                        if let translatedText = story.translatedText, !translatedText.characters.isEmpty {
                            Text(translatedText)
                                .foregroundStyle(themeManager.currentTheme == .dark ? .green.opacity(0.9) : .green)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .id("translatedText")
                                .onChange(of: story.translatedText) { _, _ in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("translatedText", anchor: .bottom)
                                    }
                                }
                        } else {
                            Text("翻译将在这里显示...")
                                .foregroundStyle(themeManager.currentTheme == .dark ? .green.opacity(0.5) : .green.opacity(0.6))
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(themeManager.currentTheme == .dark ? Color.green.opacity(0.1) : Color.green.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // 录音控制按钮 - 更小，适配主题
                VStack(spacing: 8) {
                    if isStoppingRecording {
                        VStack(spacing: 2) {
                            Text("停止录音中...")
                                .foregroundStyle(themeManager.currentTheme == .dark ? .white : .primary)
                                .font(.caption2)
                            
                            if stopCountdown > 0 {
                                Text("\(stopCountdown)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                    } else if isGeneratingTitleAndSummary {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("AI 正在生成标题和摘要...")
                            }
                            .foregroundStyle(themeManager.currentTheme == .dark ? .white : .primary)
                            .font(.caption2)
                            
                            Text("请稍候，即将完成")
                                .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.6) : .primary.opacity(0.6))
                                .font(.caption2)
                        }
                    }
                    
                    Button {
                        if isRecording {
                            stopRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red : (isGeneratingTitleAndSummary ? Color.orange : Color.gray))
                                .frame(width: 60, height: 60)
                            
                            if isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            } else if isGeneratingTitleAndSummary {
                                Image(systemName: "brain")
                                    .foregroundColor(.white)
                                    .font(.title3)
                            } else {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .scaleEffect(isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
                    }
                    .disabled(isStoppingRecording || isGeneratingTitleAndSummary)
                    
                    Text(isRecording ? "点击停止录音" : (isGeneratingTitleAndSummary ? "AI 处理中..." : "录音已完成"))
                        .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.8) : .primary.opacity(0.8))
                        .font(.caption2)
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            setupRecording()
        }
        .onDisappear {
            cleanupRecording()
        }
        .translationTask(
            TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceLanguage.rawValue),
                target: Locale.Language(identifier: targetLanguage.rawValue)
            )
        ) { session in
            translationSession = session
            speechTranscriber?.setTranslationSession(session)
        }
    }
    
    private func setupRecording() {
        print("🎬 FullScreenRecordingView setupRecording started")
        
        // 创建转录器和录音器
        speechTranscriber = SpokenWordTranscriber(story: Binding(
            get: { story },
            set: { _ in }
        ))
        print("🎬 SpokenWordTranscriber created")
        
        recorder = Recorder(transcriber: speechTranscriber, story: Binding(
            get: { story },
            set: { _ in }
        ))
        print("🎬 Recorder created")
        
        // 设置语言
        Task {
            print("🎬 Setting up language settings: \(sourceLanguage.rawValue) -> \(targetLanguage.rawValue)")
            await speechTranscriber.updateLanguageSettings(
                sourceLanguage: sourceLanguage.rawValue,
                targetLanguage: targetLanguage.rawValue
            )
            print("🎬 Language settings updated")
            
            // 自动开始录音
            print("🎬 Starting recording...")
            await startRecording()
        }
    }
    
    private func startRecording() async {
        print("🎬 startRecording called")
        guard let recorder = recorder else { 
            print("❌ recorder is nil")
            return 
        }
        
        print("🎬 Requesting microphone authorization...")
        await recorder.requestMicAuthorization()
        
        if recorder.isMicAuthorized {
            print("✅ Microphone authorized")
            await MainActor.run {
                isRecording = true
                print("🎬 isRecording set to true")
            }
            
            do {
                print("🎬 Starting actual recording...")
                try await recorder.record()
                print("✅ Recording started successfully")
            } catch {
                print("❌ Recording failed: \(error)")
                await MainActor.run {
                    isRecording = false
                }
            }
        } else {
            print("❌ Microphone not authorized")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isStoppingRecording = true
        stopCountdown = 3
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            stopCountdown -= 1
            
            if stopCountdown <= 0 {
                timer.invalidate()
                
                Task {
                    try? await recorder?.stopRecording()
                    try? await speechTranscriber?.finishTranscribing()
                    
                    await MainActor.run {
                        story.isDone = true
                        isRecording = false
                        isStoppingRecording = false
                        isGeneratingTitleAndSummary = true
                    }
                    
                    // 生成标题和摘要
                    await generateTitleAndSummary()
                    
                    // 跳转到详情页
                    await MainActor.run {
                        isGeneratingTitleAndSummary = false
                        onDismiss(story)
                    }
                }
            }
        }
    }
    
    private func generateTitleAndSummary() async {
        let transcriptText = String(story.text.characters)
        let translatedText = story.translatedText != nil ? String(story.translatedText!.characters) : ""
        
        print("🔄 开始生成标题和摘要...")
        print("📝 转录文本长度: \(transcriptText.count)")
        print("🌐 翻译文本长度: \(translatedText.count)")
        
        guard !transcriptText.isEmpty else { 
            print("❌ 转录文本为空，跳过生成")
            return 
        }
        
        // 读取提示词模板
        let prompt: String
        if let templatePath = Bundle.main.path(forResource: "PromptTemplate", ofType: "txt"),
           let template = try? String(contentsOfFile: templatePath, encoding: .utf8) {
            // 使用模板文件，替换占位符
            prompt = template.replacingOccurrences(of: "{{TRANSCRIPT_TEXT}}", with: transcriptText)
            print("📄 使用模板文件生成提示词")
        } else {
            // 如果模板文件不存在，使用默认提示词
            prompt = """
            请根据以下语音转录内容，生成标题和摘要。

            请严格按照以下 JSON 格式返回，不包含任何其他额外文字：

            {
              "title": "生成的标题",
              "original_summary": "English summary of the content...",
              "translated_summary": "中文摘要内容..."
            }

            语音转录内容：
            \(transcriptText)
            """
            print("⚠️ 模板文件未找到，使用默认提示词")
        }
        
        print("🤖 发送提示词到 LLM...")
        print("⏳ 用户界面显示: AI 正在生成标题和摘要...")
        
        do {
            // 使用 APIManager 调用 LLM
            let response = try await callLLM(prompt: prompt)
            print("✅ LLM 响应: \(response)")
            print("🎯 AI 处理完成，准备解析结果...")
            
            // 清理响应，移除可能的markdown代码块标记
            let cleanedResponse = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("🧹 清理后的响应: \(cleanedResponse)")
            
            // 解析 JSON 响应
            guard let data = cleanedResponse.data(using: .utf8) else {
                print("❌ 无法将响应转换为 Data")
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("📋 解析的 JSON: \(json ?? [:])")
                
                if let title = json?["title"] as? String {
                    print("🎯 提取到标题: \(title)")
                    
                    // 尝试提取新格式的摘要字段
                    let originalSummary = json?["original_summary"] as? String
                    let translatedSummary = json?["translated_summary"] as? String
                    
                    // 如果新格式不存在，尝试旧格式
                    let fallbackSummary = json?["summary"] as? String
                    
                    let finalOriginalSummary = originalSummary ?? fallbackSummary ?? ""
                    let finalTranslatedSummary = translatedSummary ?? fallbackSummary ?? ""
                    
                    print("📄 提取到原文摘要: \(finalOriginalSummary.isEmpty ? "无" : "有内容")")
                    print("📄 提取到中文摘要: \(finalTranslatedSummary.isEmpty ? "无" : "有内容")")
                    
                    if !finalOriginalSummary.isEmpty {
                        await MainActor.run {
                            story.title = title
                            story.originalSummary = finalOriginalSummary
                            story.chineseSummary = finalTranslatedSummary.isEmpty ? finalOriginalSummary : finalTranslatedSummary
                            print("✅ 已更新 story 的标题和摘要")
                        }
                    } else {
                        print("❌ 摘要内容为空，设置默认值")
                        await MainActor.run {
                            story.title = title
                            story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                            story.chineseSummary = story.originalSummary
                            print("🔄 已设置默认摘要")
                        }
                    }
                } else {
                    print("❌ JSON 格式不正确，无法提取 title")
                    // 设置默认值
                    await MainActor.run {
                        story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                        story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                        story.chineseSummary = story.originalSummary
                        print("🔄 已设置默认标题和摘要")
                    }
                }
            } catch {
                print("❌ JSON 解析错误: \(error)")
                // 设置默认值
                await MainActor.run {
                    story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                    story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                    story.chineseSummary = story.originalSummary
                    print("🔄 已设置默认标题和摘要")
                }
            }
            
        } catch {
            print("❌ LLM 调用失败: \(error)")
            // 设置默认值
            await MainActor.run {
                story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                story.chineseSummary = story.originalSummary
                print("🔄 已设置默认标题和摘要")
            }
        }
    }
    
    private func callLLM(prompt: String) async throws -> String {
        print("🔗 准备调用 LLM API...")
        print("🎯 Provider: \(apiManager.selectedProvider.rawValue)")
        print("🤖 Model: \(apiManager.selectedModel.id)")
        
        guard let url = URL(string: "\(apiManager.selectedProvider.baseURL)/chat/completions") else {
            print("❌ 无效的 URL: \(apiManager.selectedProvider.baseURL)/chat/completions")
            throw URLError(.badURL)
        }
        
        let rawApiKey = apiManager.apiKeys[apiManager.selectedProvider.rawValue] ?? ""
        let apiKey = rawApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !apiKey.isEmpty else {
            print("❌ API Key 为空")
            throw URLError(.userAuthenticationRequired)
        }
        
        // 检查是否清理了空白字符
        if rawApiKey != apiKey {
            print("🧹 API Key 已清理空白字符: 原长度 \(rawApiKey.count) -> 清理后 \(apiKey.count)")
        }
        
        print("🔑 API Key 已配置 (长度: \(apiKey.count))")
        print("🔑 API Key 前缀: \(String(apiKey.prefix(15)))...")
        print("🔑 API Key 后缀: ...\(String(apiKey.suffix(6)))")
        
        // 检查 OpenRouter API Key 格式
        if apiManager.selectedProvider.rawValue == "openrouter" {
            print("🔍 OpenRouter API Key 详细信息:")
            print("   - 前缀: \(String(apiKey.prefix(15)))")
            print("   - 长度: \(apiKey.count)")
            print("   - 是否以 sk-or- 开头: \(apiKey.hasPrefix("sk-or-"))")
            
            // 检查 API Key 是否包含不可见字符
            let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedKey != apiKey {
                print("⚠️ 警告: API Key 包含空白字符，已清理")
                print("   - 原长度: \(apiKey.count)")
                print("   - 清理后长度: \(cleanedKey.count)")
            }
            
            if !apiKey.hasPrefix("sk-or-") {
                print("⚠️ 警告: OpenRouter API Key 应该以 'sk-or-' 开头")
                print("💡 提示: 请检查您的 API Key 是否正确")
                print("🔍 实际前缀: '\(String(apiKey.prefix(6)))'")
            }
            if apiKey.count < 50 {
                print("⚠️ 警告: OpenRouter API Key 长度可能不正确 (通常 > 50 字符)")
            }
        }
        
        var requestBody: [String: Any] = [
            "model": apiManager.selectedModel.id,
            "messages": [
                [
                    "role": "system", 
                    "content": "你是一个专业的语音记录助手。请根据用户提供的语音转录内容，生成简洁的标题和详细的摘要。请严格按照JSON格式返回结果，包含title、original_summary和translated_summary三个字段，不要包含任何其他文字。"
                ],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 1200
        ]
        
        // 只有 OpenAI 支持 response_format，OpenRouter 可能不支持
        if apiManager.selectedProvider.rawValue == "openai" {
            requestBody["response_format"] = ["type": "json_object"]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // 根据不同提供商设置认证方式
        if apiManager.selectedProvider.rawValue == "openrouter" {
            // OpenRouter 特殊设置 - 按照官方文档的顺序设置头部
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://voxmind.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("VoxMind", forHTTPHeaderField: "X-Title")
            
            print("🔧 OpenRouter 头部设置:")
            print("   - Authorization: Bearer \(String(apiKey.prefix(10)))...***")
            print("   - Content-Type: application/json")
            print("   - HTTP-Referer: https://voxmind.app")
            print("   - X-Title: VoxMind")
            
            // 验证 API Key 是否正确截断显示
            let keyPrefix = String(apiKey.prefix(15))
            let keySuffix = String(apiKey.suffix(4))
            print("🔑 完整 API Key 检查: \(keyPrefix)...\(keySuffix) (长度: \(apiKey.count))")
            
        } else {
            // 其他提供商使用标准认证
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("📤 发送请求到: \(url)")
        print("📋 请求头:")
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            if key == "Authorization" {
                print("   \(key): Bearer \(String(apiKey.prefix(10)))...***")
            } else {
                print("   \(key): \(value)")
            }
        }
        
        if let bodyData = request.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("📝 请求体: \(bodyString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📥 HTTP 状态码: \(httpResponse.statusCode)")
        }
        
        // 打印原始响应
        if let responseString = String(data: data, encoding: .utf8) {
            print("📄 原始响应: \(responseString)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ 无法解析响应为 JSON")
            throw URLError(.cannotParseResponse)
        }
        
        // 检查是否有错误
        if let error = json["error"] as? [String: Any] {
            let errorMessage = error["message"] as? String ?? "未知错误"
            print("❌ API 错误: \(errorMessage)")
            throw URLError(.badServerResponse)
        }
        
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("❌ 响应格式不正确")
            print("📋 完整响应: \(json)")
            throw URLError(.cannotParseResponse)
        }
        
        print("✅ 成功获取 LLM 响应")
        return content
    }
    
    private func cleanupRecording() {
        speechTranscriber?.clearTranslationSession()
        translationSession = nil
    }
}



struct ContentView: View {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var apiManager = APIManager()
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isSearching = false
    
    // 全屏录音相关状态
    @State private var showFullScreenRecording = false
    @State private var recordingStory: VoiceLog?
    @State private var recordingSourceLanguage: VoiceLogDetailView.LanguageOption = .english
    @State private var recordingTargetLanguage: VoiceLogDetailView.LanguageOption = .chinese
    @State private var showRecordingDetailView = false
    @State private var completedRecordingStory: VoiceLog?
    
    var body: some View {
        ZStack {
            // 主内容：系统TabView
            TabView(selection: $selectedTab) {
                LocalView(apiManager: apiManager, searchText: $searchText, isSearching: $isSearching)
                    .tabItem {
                        Image(systemName: "house")
                        Text("本机")
                    }
                    .tag(0)
                WidgetView()
                    .tabItem {
                        Image(systemName: "apps.iphone")
                        Text("挂件")
                    }
                    .tag(1)
                RecordView(
                    apiManager: apiManager,
                    onStartRecording: { story, sourceLanguage, targetLanguage in
                        print("🎬 onStartRecording called - setting up full screen recording")
                        recordingStory = story
                        recordingSourceLanguage = sourceLanguage
                        recordingTargetLanguage = targetLanguage
                        showFullScreenRecording = true
                        print("🎬 showFullScreenRecording set to: \(showFullScreenRecording)")
                        print("🎬 recordingStory: \(recordingStory?.title ?? "nil")")
                    }
                )
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: "mic.circle")
                    Text("录音")
                }
                .tag(2)
                SettingsView(themeManager: themeManager, apiManager: apiManager)
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("设置")
                    }
                    .tag(3)
            }
            // 悬浮的搜索按钮
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation { isSearching = true }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .shadow(radius: 2)
                    .padding(.bottom, 10)
                    .padding(.trailing, 24)
                }
            }
            // 搜索界面（全屏遮罩）
            if isSearching {
                Color.black.opacity(0.2).ignoresSafeArea()
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation { isSearching = false }
                            searchText = ""
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .padding(.trailing, 4)
                        }
                        TextField("搜索语音日志...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.vertical, 8)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                    // 搜索结果视图
                    SearchView(apiManager: apiManager, searchText: $searchText)
                    Spacer()
                }
                .background(Color(.systemBackground))
                .transition(.move(edge: .bottom))
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .onChange(of: showFullScreenRecording) { oldValue, newValue in
            print("🎬 showFullScreenRecording changed: \(oldValue) -> \(newValue)")
            print("🎬 recordingStory when changed: \(recordingStory?.title ?? "nil")")
        }
        .fullScreenCover(isPresented: $showFullScreenRecording) {
            Group {
                if let story = recordingStory {
                    FullScreenRecordingView(
                        story: story,
                        apiManager: apiManager,
                        sourceLanguage: recordingSourceLanguage,
                        targetLanguage: recordingTargetLanguage,
                        onDismiss: { completedStory in
                            showFullScreenRecording = false
                            recordingStory = nil
                            if let story = completedStory {
                                completedRecordingStory = story
                                showRecordingDetailView = true
                            }
                        }
                    )
                    .environmentObject(themeManager)
                    .onAppear {
                        print("🎬 FullScreenRecordingView appeared for story: \(story.title)")
                    }
                } else {
                    Text("错误：recordingStory 为 nil")
                        .onAppear {
                            print("❌ .fullScreenCover triggered but recordingStory is nil")
                        }
                }
            }
            .onAppear {
                print("🎬 .fullScreenCover content view appeared")
                print("🎬 showFullScreenRecording: \(showFullScreenRecording)")
                print("🎬 recordingStory: \(recordingStory?.title ?? "nil")")
            }
        }
        .sheet(isPresented: $showRecordingDetailView) {
            if let story = completedRecordingStory {
                NavigationView {
                    VoiceLogDetailView(story: story, apiManager: apiManager)
                }
            }
        }
    }
}
