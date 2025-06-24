import SwiftUI
import SwiftData
import AVFoundation
import Speech
import Translation // *** Correct Import for Translation Framework ***



// MARK: - AVAudioPlayerNode Extension (参考Apple官方实现)
extension AVAudioPlayerNode {
    var currentTime: TimeInterval {
        guard let nodeTime: AVAudioTime = self.lastRenderTime, 
              let playerTime: AVAudioTime = self.playerTime(forNodeTime: nodeTime) else { 
            return 0 
        }
        
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}

import AVFoundation

struct StoryDetailView: View {
    @Bindable var story: Story
    @ObservedObject var apiManager: APIManager
    @Environment(\.modelContext) private var modelContext
    
    enum ViewMode: CaseIterable {
        case original, translated, summary
        
        var title: String {
            switch self {
            case .original: return "Original"
            case .translated: return "Translated"
            case .summary: return "Summary"
            }
        }
    }
    
    @State private var recorder: Recorder!
    @State private var speechTranscriber: SpokenWordTranscriber!
    
    @State private var showRecordingUI = true
    @State private var selectedViewMode: ViewMode = .original
    
    @State private var totalDuration: Double = 0.0
    @State private var playbackProgressTimer: Timer?
    @State private var highlightedText: AttributedString = AttributedString("")
    
    @State private var currentPlaybackTime = 0.0
    @State private var isPlaying = false
    @State private var isRecording = false
    @State private var isStoppingRecording = false
    @State private var stopCountdown = 0
    @State private var translationPulse = false
    @State private var isGeneratingTitleAndSummary = false
    
    // 语言选择状态
    @State private var sourceLanguage: LanguageOption = .english
    @State private var targetLanguage: LanguageOption = .chinese
    @State private var showLanguageSettings = false
    @State private var supportedLanguages: Set<String> = []
    
    // 支持的语言选项
            enum LanguageOption: String, CaseIterable, Identifiable {
        case english = "en-US"
        case chinese = "zh-Hans"
        case japanese = "ja-JP"
        case korean = "ko-KR"
        case french = "fr-FR"
        case german = "de-DE"
        case spanish = "es-ES"
        case italian = "it-IT"
        case russian = "ru-RU"
        case arabic = "ar-SA"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .english: return "English"
            case .chinese: return "中文"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .french: return "Français"
            case .german: return "Deutsch"
            case .spanish: return "Español"
            case .italian: return "Italiano"
            case .russian: return "Русский"
            case .arabic: return "العربية"
            }
        }
        
        var locale: Locale {
            return Locale(identifier: rawValue)
        }
        
        var flag: String {
            switch self {
            case .english: return "🇺🇸"
            case .chinese: return "🇨🇳"
            case .japanese: return "🇯🇵"
            case .korean: return "🇰🇷"
            case .french: return "🇫🇷"
            case .german: return "🇩🇪"
            case .spanish: return "🇪🇸"
            case .italian: return "🇮🇹"
            case .russian: return "🇷🇺"
            case .arabic: return "🇸🇦"
            }
        }
    }
    
    // Access translation status directly from the @Observable transcriber
    private var translationModelStatus: SpokenWordTranscriber.TranslationModelStatus {
        speechTranscriber?.translationModelStatus ?? .notDownloaded
    }
    
    // 计算有效的播放时长（基于转录时间）
    private var effectivePlaybackDuration: Double {
        let savedTimeRanges = story.getAudioTimeRanges()
        let lastTimeRange = savedTimeRanges.max { $0.endSeconds < $1.endSeconds }
        let transcriptionEndTime = lastTimeRange?.endSeconds ?? 0
        
        // 如果有转录时间，使用转录时间；否则使用音频文件时长
        if transcriptionEndTime > 0 {
            return transcriptionEndTime
        } else {
            return totalDuration
        }
    }
    
    init(story: Story, apiManager: APIManager) {
        self._story = Bindable(story)
        self.apiManager = apiManager
        // 确保新故事显示录制界面
        let shouldShowRecordingUI = !story.isDone
        self._showRecordingUI = State(initialValue: shouldShowRecordingUI)
        // 减少初始化时的调试打印以提高性能
    }
    
    var body: some View {
        VStack {
            if showRecordingUI {
                recordingUIView
            } else {
                postRecordingUIView
            }
        }
        .onAppear {
            setupViewOnAppear()
            loadSupportedLanguages()
            // 确保转录器使用正确的默认语言
            updateTranslationSession()
        }
        .onChange(of: story.id) { _, newStoryId in
            setupViewOnAppear()
        }
        .onChange(of: sourceLanguage) { _, newLanguage in
            print("🌐 Source language changed to: \(newLanguage.displayName)")
            print("🌐 Language supported: \(isSourceLanguageSupported)")
        }
        .onChange(of: story.isDone) { _, newValue in
            print("Story.isDone changed to: \(newValue)")
            print("Story.url: \(story.url?.absoluteString ?? "nil")")
            if newValue {
                // 确保立即更新UI状态
                Task { @MainActor in
                    showRecordingUI = false
                    // 录制完成后，默认显示 Original 标签
                    selectedViewMode = .original
                    print("Switched to post-recording UI. Auto-selected Original tab.")
                }
                
                // 录制完成后，重新加载音频文件以供播放
                if let url = story.url, let recorder = recorder {
                    Task {
                        do {
                            recorder.file = try AVAudioFile(forReading: url)
                            print("Audio file loaded for playback successfully")
                        } catch {
                            print("Failed to load audio file for playback: \(error)")
                        }
                    }
                }
            } else {
                // 当 isDone 变为 false 时，显示录制界面
                Task { @MainActor in
                    showRecordingUI = true
                    print("Story.isDone changed to false, switched to recording UI")
                }
            }
        }
        .onChange(of: isRecording) { _, newValue in
            handleRecordingStateChange(newValue)
        }
        .onChange(of: translationModelStatus) { _, newStatus in
            if case .ready = newStatus {
                if selectedViewMode == .original && story.translatedText != nil {
                    selectedViewMode = .translated
                }
            }
        }
        .onDisappear {
            cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("stopAllPlayback"), object: nil)) { _ in
            // 停止当前播放
            if isPlaying {
                isPlaying = false
                recorder?.stopPlaying()
            }
        }
        .translationTask(
            TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceLanguage.rawValue),
                target: Locale.Language(identifier: targetLanguage.rawValue)
            )
        ) { session in
            // Set the translation session in the transcriber
            print("📱 StoryDetailView: Translation session created for \(sourceLanguage.displayName) → \(targetLanguage.displayName)")
            speechTranscriber?.setTranslationSession(session)
            print("📱 StoryDetailView: Translation session set successfully")
        }
        .id("\(sourceLanguage.rawValue)-\(targetLanguage.rawValue)") // 强制重新创建翻译任务
    }
    
    // MARK: - Language Selection Methods
    
    private func updateTranslationSession() {
        print("🔄 Language changed: \(sourceLanguage.displayName) → \(targetLanguage.displayName)")
        
        Task {
            // 更新转录器的语言设置
            await speechTranscriber?.updateLanguageSettings(
                sourceLanguage: sourceLanguage.rawValue,
                targetLanguage: targetLanguage.rawValue
            )
            
            // 不要立即清除翻译会话，让SwiftUI自然地重新创建
            // speechTranscriber?.clearTranslationSession()
        }
        
        // SwiftUI 会自动检测到 sourceLanguage 和 targetLanguage 的变化，
        // 并重新创建 translationTask，这会自动调用setTranslationSession
    }
    
    private func loadSupportedLanguages() {
        Task {
            if let transcriber = speechTranscriber {
                let supported = await transcriber.getSupportedLocales()
                await MainActor.run {
                    supportedLanguages = supported
                    print("🌐 Loaded supported languages: \(supported)")
                    print("🌐 Current source language \(sourceLanguage.rawValue) supported: \(isSourceLanguageSupported)")
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var languageSupportStatusView: some View {
        VStack(spacing: 8) {
            // 语音识别支持状态
            HStack {
                Image(systemName: isSourceLanguageSupported ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isSourceLanguageSupported ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("语音识别")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(sourceLanguageSupportText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            // 翻译支持状态（翻译功能通常支持更多语言）
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("翻译功能")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("支持 \(sourceLanguage.displayName) → \(targetLanguage.displayName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSourceLanguageSupported ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSourceLanguageSupported ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // 计算属性：检查源语言是否支持
    private var isSourceLanguageSupported: Bool {
        if supportedLanguages.isEmpty {
            return true // 如果还没加载支持列表，先显示为支持
        }
        
        let targetLang = sourceLanguage.rawValue
        
        // 检查完全匹配
        if supportedLanguages.contains(targetLang) {
            return true
        }
        
        // 检查各种格式变体
        let variants = [
            targetLang.replacingOccurrences(of: "-", with: "_"),
            targetLang.replacingOccurrences(of: "_", with: "-"),
            String(targetLang.prefix(2)), // 例如 "en" from "en-US"
            targetLang + "-US", // 添加US后缀
            targetLang + "_US"  // 添加US后缀（下划线版本）
        ]
        
        return variants.contains { supportedLanguages.contains($0) }
    }
    
    // 计算属性：源语言支持状态文本
    private var sourceLanguageSupportText: String {
        if supportedLanguages.isEmpty {
            return "正在检测语言支持..."
        } else if isSourceLanguageSupported {
            return "支持 \(sourceLanguage.displayName) 语音识别"
        } else {
            return "不支持 \(sourceLanguage.displayName)，将使用系统默认语言"
        }
    }
    
    private var realTimeTranslationSubtitleView: some View {
        VStack(spacing: 8) {
            // 字幕标题
            HStack {
                Image(systemName: "translate")
                    .foregroundColor(.accentColor) // 使用系统强调色，适配明暗模式
                Text("实时翻译")
                    .font(.caption)
                    .fontWeight(.semibold) // 稍微加粗标题
                    .foregroundColor(.accentColor) // 使用系统强调色
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // 翻译内容 - 带自动滚动
            ScrollViewReader { proxy in
                ScrollView {
                    VStack {
                                        if let translatedText = story.translatedText, !NSAttributedString(translatedText).string.isEmpty {
                    Text(translatedText)
                                .font(.subheadline) // 比原文的title3更小
                                .fontWeight(.regular) // 常规粗细，与原文的默认粗细形成对比
                                .foregroundColor(.primary) // 适配明暗模式的主要文字颜色
                                .lineSpacing(2) // 增加行间距，提高可读性
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    // 为翻译文字添加微妙的背景
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.05))
                                )
                        } else {
                            Text("等待翻译...")
                                .font(.subheadline)
                                .fontWeight(.light) // 更轻的字重，表示等待状态
                                .foregroundColor(Color.secondary.opacity(0.7)) // 使用次要颜色的透明版本
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        
                        // 添加一个不可见的底部锚点
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .frame(maxHeight: 120) // 限制字幕区域高度
                .onChange(of: story.translatedText) { _, newValue in
                    // 当翻译文本更新时，自动滚动到底部并触发脉动动画
                    if newValue != nil && !NSAttributedString(newValue!).string.isEmpty {
                        // 触发脉动动画
                        withAnimation(.easeInOut(duration: 0.3)) {
                            translationPulse = true
                        }
                        
                        // 延迟滚动到底部
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                        
                        // 重置脉动动画
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                translationPulse = false
                            }
                        }
                    }
                }
            }
        }
        .background(
            // 添加适配明暗模式的渐变背景
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.accentColor.opacity(0.08),
                    Color.accentColor.opacity(0.03)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1.5)
        )
        .cornerRadius(12)
        .shadow(color: Color.primary.opacity(0.08), radius: 3, x: 0, y: 1)
        .scaleEffect(translationPulse ? 1.02 : 1.0) // 添加脉动效果
        .padding(.horizontal)
        .padding(.bottom, 16)
    }
    
    private var recordingUIView: some View {
        VStack {
            if !isRecording && !isStoppingRecording && String(story.text.characters).isEmpty && !story.isDone {
                // 空白 Story - 显示大录制按钮在中央
                VStack {
                    Spacer()
                    
                    VStack(spacing: 24) {
                        // 语言选择区域
                        VStack(spacing: 12) {
                            Text("语言设置")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 12) {
                                HStack(spacing: 16) {
                                    // 源语言选择
                                    VStack(spacing: 6) {
                                        Text("说话语言")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Menu {
                                            ForEach(LanguageOption.allCases) { language in
                                                Button {
                                                    sourceLanguage = language
                                                    updateTranslationSession()
                                                } label: {
                                                    HStack {
                                                        Text(language.flag)
                                                        Text(language.displayName)
                                                        if language == sourceLanguage {
                                                            Spacer()
                                                            Image(systemName: "checkmark")
                                                        }
                                                        // 显示不支持的语言
                                                        if !supportedLanguages.isEmpty && !supportedLanguages.contains(language.rawValue) {
                                                            Spacer()
                                                            Image(systemName: "exclamationmark.triangle")
                                                                .foregroundColor(.orange)
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(sourceLanguage.flag)
                                                    .font(.callout)
                                                Text(sourceLanguage.displayName)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(6)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    // 箭头
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.accentColor)
                                        .font(.title3)
                                        .frame(width: 24)
                                    
                                    // 目标语言选择
                                    VStack(spacing: 6) {
                                        Text("翻译语言")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Menu {
                                            ForEach(LanguageOption.allCases) { language in
                                                Button {
                                                    targetLanguage = language
                                                    updateTranslationSession()
                                                } label: {
                                                    HStack {
                                                        Text(language.flag)
                                                        Text(language.displayName)
                                                        if language == targetLanguage {
                                                            Spacer()
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(targetLanguage.flag)
                                                    .font(.callout)
                                                Text(targetLanguage.displayName)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(6)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                
                                // 语言支持状态提示
                                languageSupportStatusView
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1),
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                        
                        // 录制按钮 - 毛玻璃效果
                        Button {
                            handleRecordButtonTap()
                        } label: {
                            VStack(spacing: 16) {
                                Image(systemName: "record.circle.fill")
                                    .font(.system(size: 80, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
                                
                                Text("开始录制")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.2),
                                                Color.clear
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .scaleEffect(recorder == nil ? 0.95 : 1.0)
                            .opacity(recorder == nil ? 0.6 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .disabled(recorder == nil)
                        .animation(.easeInOut(duration: 0.2), value: recorder == nil)
                    }

                    
                    Spacer()
                }
            } else {
                // 正在录制或有内容 - 显示转录文本和控件
                VStack(spacing: 0) {
                    // 原文转录区域 - 毛玻璃效果
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                            // 已确定的转录文字
                            if let transcriber = speechTranscriber, !transcriber.finalizedTranscript.characters.isEmpty {
                                HStack(alignment: .top, spacing: 0) {
                                    Text(transcriber.finalizedTranscript)
                                        .font(.title3)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                            
                            // 临时态转录文字（正在识别中的文字）
                            if let transcriber = speechTranscriber, !transcriber.volatileTranscript.characters.isEmpty {
                                HStack(alignment: .top, spacing: 0) {
                                    Text(transcriber.volatileTranscript)
                                        .font(.title3)
                                        .foregroundColor(.orange.opacity(0.8))
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .italic()
                                    Spacer(minLength: 0)
                                }
                            }
                            
                            // 确保即使没有文字时也有占位空间
                            if let transcriber = speechTranscriber, 
                               transcriber.finalizedTranscript.characters.isEmpty && 
                               transcriber.volatileTranscript.characters.isEmpty {
                                HStack {
                                    Text("开始说话...")
                                        .font(.title3)
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .italic()
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120)
                    .contentShape(Rectangle())
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1),
                                        Color.clear
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
                    .padding(.bottom)
                    
                    // 显示停止倒计时状态
                    if isStoppingRecording {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            
                            Text("正在完成转录和最终翻译...")
                                .font(.headline)
                                .foregroundColor(.orange)
                            
                            Text("剩余 \(stopCountdown) 秒")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("最后将进行完整文本的全量翻译")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding()
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange.opacity(0.3), .orange.opacity(0.1)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.orange.opacity(0.4),
                                            Color.orange.opacity(0.2),
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .orange.opacity(0.2), radius: 8, x: 0, y: 4)
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    
                    Spacer()
                    
                    // 实时翻译字幕区域
                    if isRecording {
                        realTimeTranslationSubtitleView
                    }
                    
                    // 录制控件已移动到导航栏
                }
            }
        }
        .padding()
        .navigationTitle(story.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isRecording {
                    Button {
                        handleRecordButtonTap()
                    } label: {
                        HStack(spacing: 8) {
                            if isStoppingRecording {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.orange)
                                Text("\(stopCountdown)")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Text("停止")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.5),
                                            Color.white.opacity(0.2),
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                        .scaleEffect(isStoppingRecording ? 0.95 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStoppingRecording)
                    .animation(.easeInOut(duration: 0.2), value: isStoppingRecording)
                }
            }
        }
    }
    
    private var postRecordingUIView: some View {
        VStack {
            Picker("View", selection: $selectedViewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom)
            
            switch selectedViewMode {
            case .original:
                if let recorder = recorder {
                    OriginalTextView(story: story, recorder: recorder)
                        .navigationTitle(story.title)
                } else {
                    Text("Loading...")
                        .navigationTitle(story.title)
                }
            case .translated:
                TranslatedTextView(story: story, translationModelStatus: Binding.constant(translationModelStatus), speechTranscriber: speechTranscriber)
                    .navigationTitle(story.title)
            case .summary:
                SummaryView(story: story, apiManager: apiManager)
                    .navigationTitle(story.title)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupViewOnAppear() {
        // 减少调试打印以提高性能
        
        // 创建或更新转录器和录制器，确保绑定正确的Story
        let storyBinding = Binding<Story>(
            get: { self.story },
            set: { newStory in 
                // Story binding updated
            }
        )
        
        // 如果转录器已存在，更新其Story绑定；否则创建新的
        if let existingTranscriber = self.speechTranscriber {
            existingTranscriber.updateStoryBinding(storyBinding)
        } else {
            let transcriber = SpokenWordTranscriber(story: storyBinding)
            // Only reset transcription for new/incomplete stories
            if !story.isDone {
                transcriber.resetTranscription()
            }
            self.speechTranscriber = transcriber
        }
        
        // 只在需要时创建新的录制器，避免重复创建
        if recorder == nil, let transcriber = self.speechTranscriber {
            self.recorder = Recorder(transcriber: transcriber, story: storyBinding)
            print("Created new Recorder for story: \(story.id)")
        }
        
        if story.isDone {
            showRecordingUI = false
            let hasTranslatedText = story.translatedText != nil && !NSAttributedString(story.translatedText!).string.isEmpty
            selectedViewMode = hasTranslatedText ? .translated : .original
            if let url = story.url {
                do {
                    self.recorder.file = try AVAudioFile(forReading: url)
                } catch {
                    print("StoryDetailView: Failed to load audio file for playback: \(error)")
                }
            }
        } else {
            // 确保新故事显示录制界面
            showRecordingUI = true
            Task {
                await self.recorder.requestMicAuthorization()
            }
        }
    }
    
    private func handleRecordingStateChange(_ newValue: Bool) {
        print("Recording state changed to: \(newValue)")
        guard let recorder = recorder else { 
            print("Recorder is nil!")
            return 
        }
        if newValue {
            print("Starting recording...")
            Task { @MainActor in
                do {
                    try await recorder.record()
                    print("Recording started successfully")
                } catch {
                    print("StoryDetailView: Error recording: \(error)")
                    isRecording = false
                }
            }
        } else {
            // 只有在非延迟停止状态下才处理普通的停止录制
            if !isStoppingRecording {
                print("Stopping recording...")
                Task {
                    try await recorder.stopRecording()
                    print("Recording stopped")
                    
                    // 生成标题和摘要
                    await generateTitleAndSummaryForStory()
                }
            } else {
                print("Recording state changed to false during delayed stop - skipping duplicate stop")
            }
        }
    }
    
    private func cleanup() {
        print("StoryDetailView cleanup called")
        
        // 立即清理 TranslationSession 引用，防止后续异步操作使用无效的session
        print("🧹 Clearing translation session reference")
        speechTranscriber?.clearTranslationSession()
        print("🧹 Translation session cleared successfully")
        
        // 停止所有音频活动
        if isPlaying {
            recorder?.stopPlaying()
            isPlaying = false
        }
        if isRecording {
            isRecording = false
            // 如果正在录制，尝试优雅地停止
            if let recorder = recorder {
                Task {
                    do {
                        try await recorder.stopRecording()
                        print("Recording stopped during cleanup")
                    } catch {
                        print("Error stopping recording during cleanup: \(error)")
                    }
                }
            }
        }
        
        // 清理计时器
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = nil
        
        // 重置状态
        currentPlaybackTime = 0.0
        isStoppingRecording = false
        stopCountdown = 0
        
        print("Cleanup completed")
    }
    
    private func handleRecordButtonTap() {
        print("Record button tapped. Current isRecording: \(isRecording), story.isDone: \(story.isDone)")
        print("Recorder mic authorized: \(recorder?.isMicAuthorized ?? false)")
        print("Story text before recording: '\(String(story.text.characters))'")
        print("Story ID: \(story.id)")
        
        if story.isDone {
            isRecording = false
        } else if isRecording {
            // 如果正在录制，开始延迟停止流程
            startDelayedStop()
        } else {
            // 开始录制逻辑
            print("About to start recording, resetting transcriber")
            print("Story text before transcriber reset: '\(String(story.text.characters))'")
            speechTranscriber?.resetTranscription()
            print("Story text after transcriber reset: '\(String(story.text.characters))'")
            print("Transcriber reset completed")
            
            // 如果麦克风未授权，先请求权限
            if let recorder = recorder, !recorder.isMicAuthorized {
                Task {
                    await recorder.requestMicAuthorization()
                    print("Microphone authorization after button tap: \(recorder.isMicAuthorized)")
                    
                    // 权限获取后再开始录制
                    if recorder.isMicAuthorized {
                        await MainActor.run {
                            self.isRecording = true
                            print("Started recording: \(self.isRecording)")
                        }
                    } else {
                        print("Microphone access denied, cannot start recording")
                    }
                }
            } else {
                // 权限已获取，直接开始录制
                isRecording = true
                print("Started recording: \(isRecording)")
            }
        }
    }
    
    private func startDelayedStop() {
        guard !isStoppingRecording else { return }
        
        print("Starting delayed stop sequence...")
        isStoppingRecording = true
        stopCountdown = 3 // 3秒倒计时
        
        // 开始倒计时
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                self.stopCountdown -= 1
                print("Stop countdown: \(self.stopCountdown)")
                
                if self.stopCountdown <= 0 {
                    timer.invalidate()
                    self.executeStopRecording()
                }
            }
        }
    }
    
    private func executeStopRecording() {
        print("Executing delayed stop recording...")
        
        // 执行实际的停止录制逻辑
        Task {
            // 先停止录制
            if let recorder = recorder {
                try await recorder.stopRecording()
                print("Recording stopped successfully")
                
                // 生成标题和摘要
                await generateTitleAndSummaryForStory()
            }
            
            // 在主线程更新UI状态
            await MainActor.run {
                self.isRecording = false
                self.isStoppingRecording = false
                self.stopCountdown = 0
                print("Recording stopped after delay - cleanup completed")
            }
        }
    }
    
    private func statusColor(_ status: SpokenWordTranscriber.TranslationModelStatus) -> Color {
        switch status {
        case .ready: return .green
        case .downloading(_): return .blue
        case .failed(_): return .red
        case .notDownloaded: return .orange
        }
    }
    
    // 生成标题和摘要的方法 - 使用统一的API调用
    private func generateTitleAndSummaryForStory() async {
        print("🎯 generateTitleAndSummaryForStory() called - Story ID: \(story.id)")
        print("🔍 Current isGeneratingTitleAndSummary state: \(isGeneratingTitleAndSummary)")
        
        // 防止重复调用
        guard !isGeneratingTitleAndSummary else {
            print("⚠️ Title and summary generation already in progress, skipping duplicate call")
            return
        }
        
        // 在主线程设置状态标志
        await MainActor.run {
            isGeneratingTitleAndSummary = true
        }
        
        defer { 
            Task { @MainActor in
                isGeneratingTitleAndSummary = false
                print("🏁 Title and summary generation completed, state reset")
            }
        }
        
        // 获取转录的文本
        let transcriptText = String(story.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果没有转录文本，则跳过生成
        guard !transcriptText.isEmpty else {
            print("❌ No transcript text available for title and summary generation")
            return
        }
        
        // 检查当前选择的 LLM Provider 的 API Key 是否设置
        let selectedProvider = LLMConfig.defaultProvider()
        let apiKey = UserDefaults.standard.string(forKey: selectedProvider.rawValue + "APIKey") ?? ""
        if apiKey.isEmpty {
            print("❌ \(selectedProvider.displayName) API Key not configured. Please set it in Settings.")
            await MainActor.run {
                story.originalSummary = "⚠️ 请在设置中配置 \(selectedProvider.displayName) API Key 以生成摘要"
                story.chineseSummary = "⚠️ 请在设置中配置 \(selectedProvider.displayName) API Key 以生成摘要"
            }
            return
        }
        
        let selectedModel = LLMConfig.defaultModel(for: selectedProvider)
        print("🚀 Generating title and summary for transcript: '\(transcriptText.prefix(100))...'")
        print("📝 Using \(selectedProvider.displayName) with model \(selectedModel.displayName)")
        print("📝 Using API Key: \(apiKey.prefix(10))...")
        
        // 显示生成中状态
        await MainActor.run {
            story.originalSummary = "🤖 正在使用 \(selectedProvider.displayName) (\(selectedModel.displayName)) 生成标题和摘要..."
            story.chineseSummary = "🤖 正在使用 \(selectedProvider.displayName) (\(selectedModel.displayName)) 生成标题和摘要..."
        }
        
        // 重试机制：最多重试3次
        var lastError: Error?
        for attempt in 1...3 {
            do {
                print("🔄 Attempt \(attempt)/3 to generate title and summary")
                
                // 使用超时包装器调用统一的标题和摘要生成方法
                let response = try await withTimeout(seconds: 30) {
                    return try await generateTitleAndSummary(for: transcriptText)
                }
                
                // 更新 UI
                await MainActor.run {
                    story.title = response.title
                    story.originalSummary = response.originalSummary
                    story.chineseSummary = response.chineseSummary
                }
                print("✅ Generated title: '\(response.title)'")
                print("✅ Generated original summary: '\(response.originalSummary.prefix(100))...'")
                print("✅ Generated Chinese summary: '\(response.chineseSummary.prefix(100))...')")
                return // 成功后退出重试循环
                
            } catch {
                lastError = error
                print("❌ Attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < 3 {
                    // 等待递增的延迟时间后重试 (1秒, 2秒)
                    let delay = TimeInterval(attempt)
                    print("⏳ Waiting \(delay) seconds before retry...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    // 更新重试状态
                    await MainActor.run {
                        story.originalSummary = "🔄 生成失败，正在重试 (\(attempt + 1)/3)..."
                        story.chineseSummary = "🔄 生成失败，正在重试 (\(attempt + 1)/3)..."
                    }
                }
            }
        }
        
        // 所有重试都失败了，显示错误信息
        await MainActor.run {
            let errorMessage = getErrorMessage(from: lastError)
            story.originalSummary = "❌ AI 摘要生成失败: \(errorMessage)"
            story.chineseSummary = "❌ AI 摘要生成失败: \(errorMessage)"
        }
        print("❌ All attempts failed. Final error: \(lastError?.localizedDescription ?? "Unknown error")")
    }
    
    // 这个方法现在使用SharedTypes中的公共方法
    
    // 错误信息处理
    private func getErrorMessage(from error: Error?) -> String {
        guard let error = error else { return "未知错误" }
        
        if let apiError = error as? APIError {
            switch apiError {
            case .noAPIKey:
                return "API Key 未配置"
            case .invalidURL:
                return "API 地址无效"
            case .invalidResponse:
                return "API 响应格式错误"
            case .apiError(let message):
                return "API 错误: \(message)"
            case .templateNotFound:
                return "提示词模板缺失"
            case .invalidJSONResponse:
                return "JSON 响应解析失败"
            }
        }
        
        if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("timed out") {
            return "请求超时，请检查网络连接"
        }
        
        if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
            return "网络连接错误"
        }
        
        return "网络或服务器错误"
    }
    
    // 超时包装器
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // 添加主要操作
            group.addTask {
                try await operation()
            }
            
            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw APIError.apiError("请求超时 (\(Int(seconds))秒)")
            }
            
            // 返回第一个完成的任务结果
            for try await result in group {
                group.cancelAll()
                return result
            }
            
            throw APIError.apiError("任务组返回空结果")
        }
    }
}

// MARK: - Sub-Views for StoryDetailView

struct TranscriptViewForRecording: View {
    @Binding var story: Story
    
    @State private var recorder: Recorder
    @State private var speechTranscriber: SpokenWordTranscriber
    
    @State private var isRecording = false
    
    init(story: Binding<Story>, recorder: Recorder, transcriber: SpokenWordTranscriber) {
        self._story = story
        self._recorder = State(initialValue: recorder)
        self._speechTranscriber = State(initialValue: transcriber)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(speechTranscriber.finalizedTranscript + speechTranscriber.volatileTranscript)
                .font(.title3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .onAppear {
            if !story.isDone && !isRecording {
                isRecording = true
                startRecording()
            }
        }
        .onChange(of: story.isDone) { _, newValue in
            if newValue && isRecording {
                isRecording = false
                stopRecording()
            }
        }
    }
    
    private func startRecording() {
        print("TranscriptViewForRecording: Starting recording...")
        Task { @MainActor in
            do {
                try await recorder.record()
            } catch {
                print("TranscriptViewForRecording: Error recording: \(error)")
                isRecording = false
            }
        }
    }
    
    private func stopRecording() {
        print("TranscriptViewForRecording: Stopping recording...")
        Task {
            try await recorder.stopRecording()
        }
    }
}

struct OriginalTextView: View {
    @Bindable var story: Story
    
    @State private var isPlaying = false
    @State private var currentPlaybackTime: Double = 0.0
    @State private var totalDuration: Double = 0.0
    @State private var highlightedText: AttributedString = AttributedString("")
    @State private var playbackProgressTimer: Timer?
    @State private var hasShownRecoveryData = false
    
    var recorder: Recorder  // Changed from @State to regular property
    
    // 计算有效的播放时长（基于转录时间）
    private var effectivePlaybackDuration: Double {
        let savedTimeRanges = story.getAudioTimeRanges()
        let lastTimeRange = savedTimeRanges.max { $0.endSeconds < $1.endSeconds }
        let transcriptionEndTime = lastTimeRange?.endSeconds ?? 0
        
        // 如果有转录时间，使用转录时间；否则使用音频文件时长
        if transcriptionEndTime > 0 {
            return transcriptionEndTime
        } else {
            return totalDuration
        }
    }
    
    init(story: Story, recorder: Recorder) {
        self.story = story
        self.recorder = recorder  // Direct assignment
    }
    
    @ViewBuilder
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading) {
                    // 显示高亮文本（播放时）或原始文本（非播放时）
                    if isPlaying {
                        Text(highlightedText)
                            .font(.title3)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                            .animation(.easeInOut(duration: 0.2), value: highlightedText)
                    } else {
                        Text(story.text)
                            .font(.title3)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            
            HStack {
                Button(action: {
                    isPlaying.toggle()
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(isPlaying ? .orange : .blue)
                }
                .disabled(story.url == nil || !story.isDone || effectivePlaybackDuration <= 0)
                .onAppear {
                    print("Play button state: url=\(story.url != nil), isDone=\(story.isDone), effectivePlaybackDuration=\(effectivePlaybackDuration)")
                }
                .onChange(of: isPlaying) { _, newValue in
                    handlePlaybackStateChange(newValue)
                }
                
                Slider(value: $currentPlaybackTime, in: 0...(effectivePlaybackDuration > 0 ? effectivePlaybackDuration : 1), step: 0.1) { editing in
                    if !editing {
                        seekToTime(currentPlaybackTime)
                    }
                }
                .disabled(story.url == nil || !story.isDone || effectivePlaybackDuration <= 0)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            print("OriginalTextView appeared. story.url: \(story.url?.absoluteString ?? "nil"), recorder.file: \(recorder.file != nil)")
            print("story.isDone: \(story.isDone)")
            loadAudioFile()
            setupTextForHighlightPlayback()
            print("After loadAudioFile - totalDuration: \(totalDuration), currentPlaybackTime: \(currentPlaybackTime)")
        }
        .onDisappear {
            stopPlaybackTimer()
            if isPlaying {
                recorder.stopPlaying()
            }
        }
    }
    
    private func loadAudioFile() {
        guard let url = story.url else {
            print("No audio URL available")
            return
        }
        
        print("Attempting to load audio file from: \(url.absoluteString)")
        print("File exists at path: \(FileManager.default.fileExists(atPath: url.path))")
        
        // Always try to load the file, don't check if recorder.file exists
        do {
            let audioFile = try AVAudioFile(forReading: url)
            // Calculate total duration
            totalDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            currentPlaybackTime = 0.0 // Reset to beginning
            print("OriginalTextView: Audio file loaded successfully for playback")
            print("  - File length: \(audioFile.length) frames")
            print("  - Sample rate: \(audioFile.fileFormat.sampleRate) Hz")
            print("  - Duration: \(totalDuration) seconds")
            print("  - Play button should now be enabled: \(story.url != nil && story.isDone && totalDuration > 0)")
            
            // Note: We don't update recorder.file here since recorder is not @State
            // The recorder will load its own copy of the file when playing
        } catch {
            print("OriginalTextView: Failed to load audio file for playback: \(error)")
            totalDuration = 0.0
            currentPlaybackTime = 0.0
        }
    }
    
    private func seekToTime(_ time: Double) {
        // For now, we'll restart playback from the beginning
        // Advanced seeking would require more complex audio engine setup
        print("Seeking to time: \(time)s (restart from beginning)")
        if isPlaying {
            recorder.stopPlaying()
            recorder.playRecording()
        }
    }
    
    private func startPlaybackTimer() {
        // 先停止任何现有的计时器
        stopPlaybackTimer()
        
        print("🎬 Starting playback timer...")
        
        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                if let player = self.recorder.playerNode {
                    // 使用Apple官方的简单方法获取播放时间
                    let newTime = player.currentTime
                    self.currentPlaybackTime = newTime
                    
                    print("⏰ Playback time: \(newTime)s, isPlaying: \(player.isPlaying)")
                    
                    // 获取转录的实际结束时间
                    let savedTimeRanges = self.story.getAudioTimeRanges()
                    let lastTimeRange = savedTimeRanges.max { $0.endSeconds < $1.endSeconds }
                    let transcriptionEndTime = lastTimeRange?.endSeconds ?? 0
                    
                    // 使用转录结束时间来判断播放是否完成
                    let effectiveEndTime = max(transcriptionEndTime, 1.0)
                    
                    // 检查播放是否应该完成
                    if self.currentPlaybackTime >= effectiveEndTime {
                        print("🏁 Playback finished - reached end time")
                        // 重置字幕高亮到开始状态
                        self.currentPlaybackTime = 0.0
                        self.updateTextHighlightForPlayback()
                        self.finishPlayback()
                        return
                    }
                    
                    // 检查播放节点是否仍在播放
                    if !player.isPlaying && self.isPlaying {
                        print("🏁 Playback finished - player stopped")
                        // 重置字幕高亮到开始状态
                        self.currentPlaybackTime = 0.0
                        self.updateTextHighlightForPlayback()
                        self.finishPlayback()
                        return
                    }
                    
                    // 更新高亮
                    if player.isPlaying {
                        print("🎨 Updating text highlight...")
                        self.updateTextHighlightForPlayback()
                    }
                } else if self.isPlaying {
                    print("🏁 Playback finished - no player node")
                    // 重置字幕高亮到开始状态
                    self.currentPlaybackTime = 0.0
                    self.updateTextHighlightForPlayback()
                    self.finishPlayback()
                }
            }
        }
        
        print("🎬 Playback timer started successfully")
    }
    
    private func finishPlayback() {
        stopPlaybackTimer()
        recorder.stopPlaying()
        isPlaying = false
        currentPlaybackTime = 0.0
        setupTextForHighlightPlayback()
        print("🎬 Playback finished and text highlighting reset")
    }
    
    private func handlePlaybackStateChange(_ newValue: Bool) {
        guard story.url != nil else { 
            print("No audio URL to play")
            return 
        }
        
        print("OriginalTextView: Play state changed to: \(newValue)")
        
        if newValue {
            // 开始播放
            print("OriginalTextView: Starting playback...")
            loadAudioFile() // Ensure file is loaded
            
            guard effectivePlaybackDuration > 0 else {
                print("OriginalTextView: Cannot play: effectivePlaybackDuration is \(effectivePlaybackDuration)")
                isPlaying = false // 重置状态
                return
            }
            
            // 开始播放时重置
            currentPlaybackTime = 0.0
            hasShownRecoveryData = false
            setupTextForHighlightPlayback()
            
            // 开始播放音频
            print("🎵 About to call recorder.playRecording()")
            recorder.playRecording()
            
            // 启动计时器（参考Apple官方实现）
            print("⏰ About to start playback timer")
            startPlaybackTimer()
        } else {
            // 停止播放
            print("⏹️ Stopping playback...")
            stopPlaybackTimer()
            recorder.stopPlaying()
            currentPlaybackTime = 0.0
            setupTextForHighlightPlayback()
        }
        
        print("OriginalTextView: Play state after change: isPlaying = \(isPlaying)")
    }
    
    private func stopPlaybackTimer() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = nil
    }
    
    private func setupTextForHighlightPlayback() {
        // 初始化时显示原始文本，无高亮
        highlightedText = story.text
        // 清除任何现有的高亮
        let fullRange = highlightedText.startIndex..<highlightedText.endIndex
        highlightedText[fullRange].backgroundColor = nil
    }
    
    // 播放时更新文本高亮的方法（简化版，参考Apple官方实现）
    private func updateTextHighlightForPlayback() {
        // 创建高亮文本的副本
        highlightedText = story.text
        
        // 先清除所有现有的高亮
        let fullRange = highlightedText.startIndex..<highlightedText.endIndex
        highlightedText[fullRange].backgroundColor = nil
        
        print("🎨 updateTextHighlightForPlayback called - currentTime: \(currentPlaybackTime)s")
        
        var highlightedRuns = 0
        
        // 获取原始文本的runs数量用于调试
        let runsCount = story.text.runs.count
        print("📝 Original text has \(runsCount) runs")
        
        // 使用与官方示例相同的高亮逻辑
        for attributedStringRun in story.text.runs {
            let start = attributedStringRun.audioTimeRange?.start.seconds
            let end = attributedStringRun.audioTimeRange?.end.seconds
            
            guard let start, let end else { continue }
            
            let runText = String(story.text[attributedStringRun.range].characters).prefix(10)
            print("🔍 Native audioTimeRange - '\(runText)...': \(start)s-\(end)s, current: \(currentPlaybackTime)s")
            
            // 官方示例的逻辑：如果结束时间小于当前时间，不高亮
            if end < currentPlaybackTime { continue }
            
            // 如果当前时间在开始和结束之间，高亮
            if start < currentPlaybackTime && currentPlaybackTime < end {
                highlightedText[attributedStringRun.range].backgroundColor = .mint.opacity(0.2)
                highlightedRuns += 1
                print("🎯 Highlighted native range: '\(runText)...' (\(start)s-\(end)s)")
                break // 只高亮第一个匹配的范围
            }
        }
        
        // 使用保存的时间范围数据进行高亮
        if story.text.runs.count == 1 && highlightedRuns == 0 {
            print("🔧 Using saved data for position-based highlighting")
            let savedTimeRanges = story.getAudioTimeRanges()
            
            for savedRange in savedTimeRanges {
                let savedStart = savedRange.startSeconds
                let savedEnd = savedRange.endSeconds
                let savedTextRange = savedRange.textRange
                
                // 使用与官方示例相同的逻辑
                if savedEnd < currentPlaybackTime { continue }
                
                if savedStart < currentPlaybackTime && currentPlaybackTime < savedEnd {
                    // 获取对应的文本范围
                    guard savedTextRange.location >= 0 && 
                          savedTextRange.location + savedTextRange.length <= highlightedText.characters.count else { continue }
                    
                    let startIndex = highlightedText.characters.index(highlightedText.characters.startIndex, offsetBy: savedTextRange.location)
                    let endIndex = highlightedText.characters.index(startIndex, offsetBy: savedTextRange.length)
                    let range = startIndex..<endIndex
                    
                    let savedRangeText = String(highlightedText[range].characters).prefix(10)
                    print("🎯 Highlighted saved range: '\(savedRangeText)...' (\(savedStart)s-\(savedEnd)s)")
                    
                    // 应用高亮到 highlightedText
                    highlightedText[range].backgroundColor = .mint.opacity(0.2)
                    highlightedRuns += 1
                    break // 只高亮第一个匹配的范围
                }
            }
        }
        
        print("🎨 Total highlighted runs: \(highlightedRuns)/\(runsCount)")
    }
}

struct TranslatedTextView: View {
    @Bindable var story: Story
    @Binding var translationModelStatus: SpokenWordTranscriber.TranslationModelStatus
    var speechTranscriber: SpokenWordTranscriber?
    
    var body: some View {
        VStack {
            switch translationModelStatus {
                case .notDownloaded:
                    VStack {
                        Text("Translation model not downloaded.")
                            .foregroundColor(.orange)
                        Button("Download Translation Model") {
                            Task {
                                await speechTranscriber?.prepareTranslationModel()
                            }
                        }
                        .padding(.top)
                    }
                case .downloading(let progress):
                    ProgressView("Downloading Translation Model...", value: progress?.fractionCompleted ?? 0, total: 1.0)
                        .padding()
                case .ready:
                    if let translatedText = story.translatedText, !NSAttributedString(translatedText).string.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading) {
                                Text(translatedText)
                                    .font(.title3)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(12)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                        }
                    } else {
                        Text("Translation is in progress or unavailable.")
                            .foregroundColor(.gray)
                    }
                case .failed(let error):
                    Text("Translation failed: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .padding()
                    
                    Button("Retry Translation") {
                        print("Retry Translation button tapped.")
                        Task {
                            if let transcriber = speechTranscriber {
                                await transcriber.retryTranslation()
                            }
                        }
                    }
                    .padding(.top)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct SummaryView: View {
    @Bindable var story: Story
    @ObservedObject var apiManager: APIManager
    @State private var isRegenerating = false
    
    init(story: Story, apiManager: APIManager) {
        self.story = story
        self.apiManager = apiManager
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let originalSummary = story.originalSummary, !originalSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(originalSummary)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                    }
                }
                
                if let chineseSummary = story.chineseSummary, !chineseSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(chineseSummary)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                    }
                }
                
                if story.originalSummary == nil && story.chineseSummary == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("摘要生成中...")
                            .font(.title3)
                            .foregroundColor(.gray)
                        
                        Text("录制完成后将自动生成英文和中文摘要")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
                
                // 显示重试按钮（当摘要包含错误信息时）
                if let originalSummary = story.originalSummary,
                   (originalSummary.contains("❌") || originalSummary.contains("⚠️")) {
                    Button {
                        regenerateSummary()
                    } label: {
                        HStack {
                            if isRegenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Image(systemName: "arrow.clockwise")
                            Text(isRegenerating ? "重新生成中..." : "重新生成摘要")
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(12)
                    }
                    .disabled(isRegenerating)
                    .padding(.top)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
    
    private func regenerateSummary() {
        guard !isRegenerating else { return }
        
        let transcriptText = String(story.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcriptText.isEmpty else { return }
        
        isRegenerating = true
        
        Task {
            await generateSummaryWithRetry(for: transcriptText)
            await MainActor.run {
                isRegenerating = false
            }
        }
    }
    
    private func generateSummaryWithRetry(for text: String) async {
        // 检查 API Key 是否设置
        let apiKey = UserDefaults.standard.string(forKey: "DeepSeekAPIKey") ?? ""
        if apiKey.isEmpty {
            await MainActor.run {
                story.originalSummary = "⚠️ 请在设置中配置 DeepSeek API Key 以生成摘要"
                story.chineseSummary = "⚠️ 请在设置中配置 DeepSeek API Key 以生成摘要"
            }
            return
        }
        
        // 显示重新生成中状态
        await MainActor.run {
            story.originalSummary = "🤖 正在重新生成摘要..."
            story.chineseSummary = "🤖 正在重新生成摘要..."
        }
        
        // 重试机制：最多重试3次
        var lastError: Error?
        for attempt in 1...3 {
            do {
                print("🔄 Manual retry attempt \(attempt)/3")
                
                // 使用超时包装器
                let response = try await withTimeout(seconds: 30) {
                    try await generateTitleAndSummary(for: text)
                }
                
                // 更新 UI
                await MainActor.run {
                    story.title = response.title
                    story.originalSummary = response.originalSummary
                    story.chineseSummary = response.chineseSummary
                }
                print("✅ Manual regeneration successful")
                return // 成功后退出重试循环
                
            } catch {
                lastError = error
                print("❌ Manual retry attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < 3 {
                    let delay = TimeInterval(attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    await MainActor.run {
                        story.originalSummary = "🔄 重新生成失败，正在重试 (\(attempt + 1)/3)..."
                        story.chineseSummary = "🔄 重新生成失败，正在重试 (\(attempt + 1)/3)..."
                    }
                }
            }
        }
        
        // 所有重试都失败了
        await MainActor.run {
            let errorMessage = getErrorMessage(from: lastError)
            story.originalSummary = "❌ 重新生成失败: \(errorMessage)"
            story.chineseSummary = "❌ 重新生成失败: \(errorMessage)"
        }
    }
    
    // 错误信息处理（复用主视图的方法）
    private func getErrorMessage(from error: Error?) -> String {
        guard let error = error else { return "未知错误" }
        
        if let apiError = error as? APIError {
            switch apiError {
            case .noAPIKey:
                return "API Key 未配置"
            case .invalidURL:
                return "API 地址无效"
            case .invalidResponse:
                return "API 响应格式错误"
            case .apiError(let message):
                return "API 错误: \(message)"
            case .templateNotFound:
                return "提示词模板缺失"
            case .invalidJSONResponse:
                return "JSON 响应解析失败"
            }
        }
        
        if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("timed out") {
            return "请求超时，请检查网络连接"
        }
        
        if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
            return "网络连接错误"
        }
        
        return "网络或服务器错误"
    }
    
    // 超时包装器（复用主视图的方法）
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw APIError.apiError("请求超时 (\(Int(seconds))秒)")
            }
            
            for try await result in group {
                group.cancelAll()
                return result
            }
            
            throw APIError.apiError("任务组返回空结果")
        }
    }
}
