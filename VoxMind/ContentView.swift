import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation
import Translation



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









struct ContentView: View {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var apiManager = APIManager()
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
    
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
                LifeLogListView()
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
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
                .onDisappear {
                    showOnboarding = false
                }
        }
    }
}
