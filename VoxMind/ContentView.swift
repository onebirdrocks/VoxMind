import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation
import Translation











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
            TabView{
                Tab("本机",systemImage: "house"){
                    NavigationStack{
                        VoiceLogListView(apiManager: apiManager, searchText: $searchText, isSearching: $isSearching)
                    }
                }
                
                Tab("挂件",systemImage: "apps.iphone"){
                        LifeLogListView()
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
                        VoiceLogListView(apiManager: apiManager, searchText: $searchText, isSearching: $isSearching)
                    }
                }
                

                
            }
            .searchable(text: $searchText,prompt: "搜索你的语音日志...")
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory{
                VoxMindAskBar()
            }

            // 主内容：系统TabView
            //TabView(selection: $selectedTab) {
            /**
            TabView() {
                VoiceLogListView(apiManager: apiManager, searchText: $searchText, isSearching: $isSearching)
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
                        Text("转录")
                    }
                    .tag(2)
                SettingsView(themeManager: themeManager, apiManager: apiManager)
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("设置")
                    }
                    .tag(3)
                
            }.searchable(text: $searchText)
             */

           
            
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
