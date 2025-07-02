import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation
import Translation

struct ContentView: View {
    @Binding var spotlightVoiceLogID: String?
    
    @Query var voiceLogs: [VoiceLog]
    
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var apiManager = APIManager()
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
    
    // 用于跳转
    @State private var navigationPath = NavigationPath()
    
    // 全屏录音相关状态
    @State private var showFullScreenRecording = false
    @State private var recordingStory: VoiceLog?
    @State private var recordingSourceLanguage: VoiceLogDetailView.LanguageOption = .english
    @State private var recordingTargetLanguage: VoiceLogDetailView.LanguageOption = .chinese
    @State private var showRecordingDetailView = false
    @State private var completedRecordingStory: VoiceLog?
    
    var body: some View {
        ZStack {
            TabView{
                Tab("本机",systemImage: "house"){
                    NavigationStack{
                        VoiceLogListView(themeManager:themeManager,apiManager: apiManager, searchText: $searchText, isSearching: $isSearching)
                    }
                }
                
                Tab("挂件",systemImage: "apps.iphone"){
                    NavigationStack{
                        LifeLogListView()
                            .environmentObject(themeManager)
                    }
                }
                
                Tab("转录",systemImage: "mic.circle"){
                    NavigationStack{
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
                    }
                }
                
                Tab(role:.search){
                    NavigationStack{
                        SearchView(apiManager: apiManager, searchText: $searchText)
                    }
                }
                
                
                
            }
            .searchable(text: $searchText,prompt: "搜索你的语音日志...")
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory{
                VoxMindAskBar()
            }
            
            
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .animation(.easeInOut(duration: 0.5), value: themeManager.currentTheme)
        
        // 👇 从 Spotlight 唤醒时跳转
        .onChange(of: spotlightVoiceLogID) { id in
            guard let id = id, let uuid = UUID(uuidString: id) else { return }
            if let match = voiceLogs.first(where: { $0.id == uuid }) {
                selectedTab = 0
                navigationPath.append(match)
            } else {
                print("⚠️ 未找到 VoiceLog: \(id)")
            }
        }
        
        .fullScreenCover(isPresented: $showFullScreenRecording) {
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
            } else {
                Text("错误：recordingStory 为 nil")
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




/*
 NavigationStack(path: $navigationPath) {
 VoiceLogListView(
 themeManager: themeManager,
 apiManager: apiManager,
 searchText: $searchText,
 isSearching: $isSearching
 )
 .navigationDestination(for: VoiceLog.self) { log in
 VoiceLogDetailView(story: log, apiManager: apiManager)
 }
 }
 .tabItem {
 Label("本机", systemImage: "house")
 }
 .tag(0)
 */
