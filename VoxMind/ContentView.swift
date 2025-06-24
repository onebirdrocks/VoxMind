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
                validationStatus = .invalid(error.localizedDescription)
                isValidating = false
            }
        }
    }
    
    private func validateAPIKey(_ apiKey: String, for provider: LLMProvider) async throws -> Bool {
        guard let url = URL(string: "\(provider.baseURL)/models") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            return httpResponse.statusCode == 200
        }
        
        return false
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
                                Text(apiManager.isValidating ? "验证中..." : "验证并保存")
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
                        TextField("请输入 Limitless.AI API Key", text: $limitlessAPIKey)
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
        }
    }
    
    private func iconForTheme(_ theme: ThemeManager.AppTheme) -> String {
        switch theme {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "gear"
        }
    }
}

// 本机视图（原VoiceLog列表）
struct LocalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Story.title) private var stories: [Story]
    @State private var selection: Story?
    @State private var showingDeleteAlert = false
    @State private var storyToDelete: Story?
    @ObservedObject var apiManager: APIManager
    @Binding var searchText: String
    @Binding var isSearching: Bool
    
    private var filteredStories: [Story] {
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
    private func deleteStory(_ story: Story) {
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
        
        storyToDelete = nil as Story?
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
                        
                        let newStory = Story.blank()
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
                StoryDetailView(story: selectedStory, apiManager: apiManager)
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
            VStack(spacing: 30) {
                Image(systemName: "apps.iphone")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)
                
                Text("挂件功能")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("小组件和快捷方式功能即将推出")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("桌面小组件", systemImage: "rectangle.3.group")
                    Label("Siri 快捷指令", systemImage: "mic.badge.plus")
                    Label("控制中心集成", systemImage: "control")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("挂件")
        }
    }
}

// 录音视图
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var apiManager: APIManager
    @State private var currentStory: Story?
    // 动态语言支持
    @State private var selectedInputLanguage: StoryDetailView.LanguageOption = .chinese
    @State private var selectedTargetLanguage: StoryDetailView.LanguageOption = .english
    @State private var supportedLanguages: Set<String> = []
    // 页面加载时拉取支持的语言
    private func loadSupportedLanguages() {
        Task {
            let transcriber = SpokenWordTranscriber(story: .constant(Story.blank()))
            let supported = await transcriber.getSupportedLocales()
            await MainActor.run {
                supportedLanguages = supported
            }
        }
    }
    
    private struct LanguageSettingsView: View {
        @Binding var selectedInputLanguage: StoryDetailView.LanguageOption
        @Binding var selectedTargetLanguage: StoryDetailView.LanguageOption
        var supportedLanguages: Set<String>
        
        private func languageMenuItem(lang: StoryDetailView.LanguageOption, selected: StoryDetailView.LanguageOption, supported: Bool) -> some View {
            HStack {
                Text(lang.flag)
                Text(lang.displayName)
                if lang == selected {
                    Spacer()
                    Image(systemName: "checkmark")
                }
                if !supported {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }
            }
            .font(.caption2)
        }
        
        private func languageMenuItemTarget(lang: StoryDetailView.LanguageOption, selected: StoryDetailView.LanguageOption) -> some View {
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
        
        private func languageMenuLabel(lang: StoryDetailView.LanguageOption) -> some View {
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
                                ForEach(StoryDetailView.LanguageOption.allCases) { lang in
                                    let supported = supportedLanguages.isEmpty || supportedLanguages.contains(lang.rawValue)
                                    Button {
                                        selectedInputLanguage = lang
                                    } label: {
                                        languageMenuItem(lang: lang, selected: selectedInputLanguage, supported: supported)
                                    }
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
                                ForEach(StoryDetailView.LanguageOption.allCases) { lang in
                                    Button {
                                        selectedTargetLanguage = lang
                                    } label: {
                                        languageMenuItemTarget(lang: lang, selected: selectedTargetLanguage)
                                    }
                                }
                            } label: {
                                languageMenuLabel(lang: selectedTargetLanguage)
                            }
                        }
                    }
                    
                    // 语音识别支持状态
                    HStack {
                        let supported = supportedLanguages.isEmpty || supportedLanguages.contains(selectedInputLanguage.rawValue)
                        Image(systemName: supported ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(supported ? .green : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("语音识别")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(supportedLanguages.isEmpty ? "正在检测语言支持..." : (supported ? "支持 " + selectedInputLanguage.displayName + " 语音识别" : "不支持 " + selectedInputLanguage.displayName + "，将使用系统默认语言"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill((supportedLanguages.isEmpty || supportedLanguages.contains(selectedInputLanguage.rawValue)) ? Color.green.opacity(0.1) : Color.orange.opacity(0.1)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke((supportedLanguages.isEmpty || supportedLanguages.contains(selectedInputLanguage.rawValue)) ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    
                    // 翻译支持状态
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("翻译功能")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("支持 \(selectedInputLanguage.displayName) → \(selectedTargetLanguage.displayName)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
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
                if let story = currentStory {
                    StoryDetailView(story: story, apiManager: apiManager)
                } else {
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
                            let newStory = Story.blank()
                            modelContext.insert(newStory)
                            currentStory = newStory
                            print("Created new story for recording: \(newStory.title)")
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
            }
            .navigationTitle("录音")
            .toolbar {
                if currentStory != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("完成") {
                            currentStory = nil
                        }
                    }
                }
            }
        }
    }
}

// 搜索视图
struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Story.title) private var stories: [Story]
    @State private var selection: Story?
    @ObservedObject var apiManager: APIManager
    @Binding var searchText: String
    
    private var filteredStories: [Story] {
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
                StoryDetailView(story: selectedStory, apiManager: apiManager)
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

struct ContentView: View {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var apiManager = APIManager()
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isSearching = false
    
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
                RecordView(apiManager: apiManager)
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
    }
}
