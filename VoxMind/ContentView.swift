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
        guard !currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
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
                        .id(apiManager.selectedProvider.id) // 重要：当Provider改变时重新创建Picker
                        
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
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("完成") {
                        dismiss()
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

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Story.title) private var stories: [Story]
    @State private var selection: Story?
    @State private var showingSettings = false
    @State private var showingDeleteAlert = false
    @State private var storyToDelete: Story?
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var apiManager = APIManager()
    
    // 停止所有音频播放的方法
    private func stopAllAudioPlayback() {
        // 通知所有当前活跃的录制器停止播放
        NotificationCenter.default.post(name: NSNotification.Name("stopAllPlayback"), object: nil)
    }
    
    // 删除单个Story的方法
    private func deleteStory(_ story: Story) {
        withAnimation {
            // 如果要删除的是当前选中的Story，清除选择
            if selection?.id == story.id {
                selection = nil
            }
            
            // 删除关联的音频文件
            if let audioURL = story.url,
               FileManager.default.fileExists(atPath: audioURL.path) {
                try? FileManager.default.removeItem(at: audioURL)
                print("Deleted audio file: \(audioURL.lastPathComponent)")
            }
            
            // 从SwiftData上下文中删除
            modelContext.delete(story)
            print("Deleted story: \(story.title)")
            
            // 保存上下文变更
            do {
                try modelContext.save()
                print("Successfully saved context after deletion")
            } catch {
                print("Failed to save context after deletion: \(error)")
            }
        }
        
        // 清理状态
        storyToDelete = nil as Story?
    }
    
    // 删除Story记录的方法（批量删除）
    private func deleteStories(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let story = stories[index]
                deleteStory(story)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(stories) { story in
                    NavigationLink(value: story) {
                        VStack(alignment: .leading) {
                            Text(story.title)
                            if story.isDone {
                                Text("Recorded & Translated")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
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
            .navigationTitle("语音日志")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    
                    Button {
                        // 停止所有当前播放的音频
                        stopAllAudioPlayback()
                        
                        let newStory = Story.blank()
                        modelContext.insert(newStory)
                        
                        // 强制更新选择，确保界面切换
                        DispatchQueue.main.async {
                            selection = newStory
                        }
                        
                        print("Created new story: \(newStory.title), isDone: \(newStory.isDone)")
                        print("Selection set to new story: \(newStory.id)")
                    } label: {
                        Label("Add Story", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selectedStory = selection {
                StoryDetailView(story: selectedStory, apiManager: apiManager)
            } else {
                Text("🎙️ Welcome to OBVoiceLab! I'll help you record, transcribe ✍️, translate 🌐, and summarize 📝 your voice logs effortlessly.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.05))
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .sheet(isPresented: $showingSettings) {
            SettingsView(themeManager: themeManager, apiManager: apiManager)
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
