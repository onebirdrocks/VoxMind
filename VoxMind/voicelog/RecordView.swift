import SwiftUI
import SwiftData

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

