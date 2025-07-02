import SwiftUI
import SwiftData

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
                (story.translatedSummary?.localizedCaseInsensitiveContains(searchText) ?? false)
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
