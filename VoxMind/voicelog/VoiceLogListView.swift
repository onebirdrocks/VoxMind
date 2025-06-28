import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation
import Translation


struct VoiceLogListView: View {
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
