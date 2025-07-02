import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation
import Translation
import AVFoundation

// 音频输入设备类型
enum AudioInputDevice {
    case builtInMic        // 内置麦克风
    case bluetoothHFP      // 蓝牙耳机 (HFP)
    case bluetoothA2DP     // 蓝牙耳机 (A2DP)
    case airPods           // AirPods
    case headsetMic        // 有线耳机麦克风
    case externalMic       // 外置麦克风
    case unknown           // 未知设备
    
    var displayName: String {
        switch self {
        case .builtInMic: return "iPhone 麦克风"
        case .bluetoothHFP: return "蓝牙耳机"
        case .bluetoothA2DP: return "蓝牙耳机"
        case .airPods: return "AirPods"
        case .headsetMic: return "有线耳机"
        case .externalMic: return "外置麦克风"
        case .unknown: return "音频设备"
        }
    }
    
    var iconName: String {
        switch self {
        case .builtInMic: return "iphone"
        case .bluetoothHFP, .bluetoothA2DP: return "headphones"
        case .airPods: return "airpods"
        case .headsetMic: return "headphones"
        case .externalMic: return "mic.external"
        case .unknown: return "mic"
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
    @State private var currentAudioInputDevice: AudioInputDevice = .unknown
    @StateObject private var waveformAnalyzer = RecordingAudioAnalyzer()
    @State private var waveformHeights: [CGFloat] = Array(repeating: 2, count: 80)
    @State private var waveformTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    @State private var durationTimer: Timer?
    
    var body: some View {
        ZStack {
            // 背景 - 根据主题使用不同的颜色
            (themeManager.currentTheme == .dark ? Color.black : Color(.systemBackground))
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // 语言显示 - 移到顶部，更紧凑
                VStack(spacing: 4) {
                    // 音频输入设备显示
                    HStack(spacing: 4) {
                        Image(systemName: currentAudioInputDevice.iconName)
                            .font(.caption2)
                            .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.6) : .primary.opacity(0.6))
                        
                        Text("\(currentAudioInputDevice.displayName) 录音中...")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.8) : .primary.opacity(0.8))
                    }
                    
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
                        } else {
                            Text("翻译将在这里显示...")
                                .foregroundStyle(themeManager.currentTheme == .dark ? .green.opacity(0.5) : .green.opacity(0.6))
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .onChange(of: story.translatedText) { _, _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("translatedText", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(themeManager.currentTheme == .dark ? Color.green.opacity(0.1) : Color.green.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // 波形显示区域 - 仅在录制时显示
                if isRecording {
                    VStack(spacing: 12) {
                        // 录制时长显示
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(.red)
                            
                            Text(formatDuration(recordingDuration))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.9) : .primary.opacity(0.9))
                            
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                                .opacity(0.8)
                                .scaleEffect(1.2)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                        }
                        
                        // 专业波形显示
                        VStack(spacing: 6) {
                            // 波形容器
                            ZStack {
                                // 背景网格线（可选）
                                HStack(spacing: 0) {
                                    ForEach(0..<8, id: \.self) { _ in
                                        Rectangle()
                                            .fill(themeManager.currentTheme == .dark ? .white.opacity(0.05) : .black.opacity(0.05))
                                            .frame(width: 1)
                                        Spacer()
                                    }
                                }
                                
                                // 波形显示
                                HStack(spacing: 1) {
                                    ForEach(0..<80, id: \.self) { index in
                                        RoundedRectangle(cornerRadius: 0.5)
                                            .fill(professionalWaveformColor(for: waveformHeights[index], index: index))
                                            .frame(width: 2, height: max(2, waveformHeights[index]))
                                            .animation(.easeInOut(duration: 0.1), value: waveformHeights[index])
                                    }
                                }
                            }
                            .frame(height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeManager.currentTheme == .dark ? .black.opacity(0.3) : .white.opacity(0.8))
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                            .padding(.horizontal)
                            
                            // 音量级别指示
                            HStack(spacing: 4) {
                                Text("音量:")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                // 音量条
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        // 背景
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(themeManager.currentTheme == .dark ? .white.opacity(0.2) : .black.opacity(0.2))
                                        
                                        // 音量指示
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(volumeLevelColor())
                                            .frame(width: geometry.size.width * currentVolumeLevel())
                                            .animation(.easeInOut(duration: 0.1), value: currentVolumeLevel())
                                    }
                                }
                                .frame(height: 4)
                                
                                Text("\(Int(currentVolumeLevel() * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
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
            updateAudioInputDevice()
            startAudioRouteChangeMonitoring()
        }
        .onDisappear {
            cleanupRecording()
            stopAudioRouteChangeMonitoring()
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
        
        // 设置音频级别回调
        recorder.audioLevelCallback = { audioLevel in
            Task { @MainActor in
                self.updateWaveformWithAudioData(audioLevel)
            }
        }
        print("🎬 Recorder created with audio level callback")
        
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
                startWaveformAnimation()
                print("🎬 isRecording set to true, 波形动画已启动")
            }
            
            do {
                print("🎬 Starting actual recording...")
                try await recorder.record()
                print("✅ Recording started successfully")
            } catch {
                print("❌ Recording failed: \(error)")
                await MainActor.run {
                    isRecording = false
                    stopWaveformAnimation()
                    print("🎬 录制失败，波形动画已停止")
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
                        stopWaveformAnimation()
                        print("🎬 录制停止，波形动画已停止")
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
                            story.translatedSummary = finalTranslatedSummary.isEmpty ? finalOriginalSummary : finalTranslatedSummary
                            SpotlightManager.shared.updateVoiceLog(vlog: story)
                            print("✅ 已更新 story 的标题和摘要")
                        }
                    } else {
                        print("❌ 摘要内容为空，设置默认值")
                        await MainActor.run {
                            story.title = title
                            story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                            story.translatedSummary = story.originalSummary
                            SpotlightManager.shared.updateVoiceLog(vlog: story)
                            print("🔄 已设置默认摘要")
                        }
                    }
                } else {
                    print("❌ JSON 格式不正确，无法提取 title")
                    // 设置默认值
                    await MainActor.run {
                        story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                        story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                        story.translatedSummary = story.originalSummary
                        SpotlightManager.shared.updateVoiceLog(vlog: story)
                        print("🔄 已设置默认标题和摘要")
                    }
                }
            } catch {
                print("❌ JSON 解析错误: \(error)")
                // 设置默认值
                await MainActor.run {
                    story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                    story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                    story.translatedSummary = story.originalSummary
                    SpotlightManager.shared.updateVoiceLog(vlog: story)
                    print("🔄 已设置默认标题和摘要")
                }
            }
            
        } catch {
            print("❌ LLM 调用失败: \(error)")
            // 设置默认值
            await MainActor.run {
                story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                story.translatedSummary = story.originalSummary
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
        stopWaveformAnimation()
        print("🎬 清理录制资源，波形动画已停止")
    }
    
    // MARK: - 音频输入设备检测
    
    private func updateAudioInputDevice() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        
        guard let currentRoute = audioSession.currentRoute.inputs.first else {
            currentAudioInputDevice = .unknown
            print("🎤 无法获取当前音频输入设备")
            return
        }
        
        let portType = currentRoute.portType
        let portName = currentRoute.portName
        
        print("🎤 当前音频输入设备:")
        print("   类型: \(portType.rawValue)")
        print("   名称: \(portName)")
        
        // 根据端口类型和名称判断设备类型
        switch portType {
        case .builtInMic:
            currentAudioInputDevice = .builtInMic
            print("🎤 检测到: iPhone 内置麦克风")
            
        case .bluetoothHFP:
            if portName.lowercased().contains("airpods") {
                currentAudioInputDevice = .airPods
                print("🎤 检测到: AirPods")
            } else {
                currentAudioInputDevice = .bluetoothHFP
                print("🎤 检测到: 蓝牙耳机 (HFP)")
            }
            
        case .bluetoothA2DP:
            if portName.lowercased().contains("airpods") {
                currentAudioInputDevice = .airPods
                print("🎤 检测到: AirPods")
            } else {
                currentAudioInputDevice = .bluetoothA2DP
                print("🎤 检测到: 蓝牙耳机 (A2DP)")
            }
            
        case .headsetMic:
            currentAudioInputDevice = .headsetMic
            print("🎤 检测到: 有线耳机麦克风")
            
        case .usbAudio:
            currentAudioInputDevice = .externalMic
            print("🎤 检测到: USB 外置麦克风")
            
        default:
            // 额外检查设备名称中是否包含已知关键字
            let lowercaseName = portName.lowercased()
            if lowercaseName.contains("airpods") {
                currentAudioInputDevice = .airPods
                print("🎤 通过名称检测到: AirPods")
            } else if lowercaseName.contains("bluetooth") || lowercaseName.contains("bt") {
                currentAudioInputDevice = .bluetoothHFP
                print("🎤 通过名称检测到: 蓝牙设备")
            } else {
                currentAudioInputDevice = .unknown
                print("🎤 检测到: 未知设备类型 - \(portType.rawValue)")
            }
        }
        #else
        // macOS 设备检测逻辑可以在此处添加
        currentAudioInputDevice = .builtInMic
        print("🎤 macOS: 使用默认音频设备")
        #endif
    }
    
    private func startAudioRouteChangeMonitoring() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("🔄 音频路由发生变化")
            
            // 延迟更新以确保路由变化完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 直接调用更新方法，SwiftUI 会自动处理状态更新
                self.updateAudioInputDevice()
            }
        }
        #endif
    }
    
    private func stopAudioRouteChangeMonitoring() {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        print("🔄 停止音频路由监听")
        #endif
    }
    
    // MARK: - 波形显示相关方法
    
    private func professionalWaveformColor(for height: CGFloat, index: Int) -> Color {
        let normalizedHeight = height / 60.0 // 基于最大高度60进行归一化
        
        // 创建类似iOS语音备忘录的渐变色彩
        if normalizedHeight > 0.8 {
            return Color(red: 1.0, green: 0.2, blue: 0.2) // 强红色
        } else if normalizedHeight > 0.6 {
            return Color(red: 1.0, green: 0.6, blue: 0.0) // 橙色
        } else if normalizedHeight > 0.4 {
            return Color(red: 0.2, green: 0.8, blue: 1.0) // 蓝色
        } else if normalizedHeight > 0.1 {
            return Color(red: 0.4, green: 0.7, blue: 1.0) // 浅蓝色
        } else {
            return Color(red: 0.6, green: 0.6, blue: 0.6).opacity(0.5) // 灰色静音
        }
    }
    
    private func volumeLevelColor() -> Color {
        let level = currentVolumeLevel()
        if level > 0.8 {
            return .red
        } else if level > 0.6 {
            return .orange
        } else if level > 0.3 {
            return .green
        } else {
            return .blue
        }
    }
    
    private func currentVolumeLevel() -> CGFloat {
        // 计算最近几个波形条的平均高度作为当前音量
        let recentCount = min(10, waveformHeights.count)
        let recentHeights = Array(waveformHeights.suffix(recentCount))
        let averageHeight = recentHeights.reduce(0, +) / CGFloat(recentCount)
        return min(averageHeight / 60.0, 1.0) // 归一化到0-1
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func startWaveformAnimation() {
        print("🌊 启动实时音频波形监听")
        // 重置波形为静默状态
        waveformHeights = Array(repeating: 2, count: 80)
        
        // 启动录制时长计时器
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.recordingDuration += 0.1
        }
    }
    
    private func stopWaveformAnimation() {
        print("🌊 停止音频波形监听")
        waveformTimer?.invalidate()
        waveformTimer = nil
        
        // 停止时长计时器
        durationTimer?.invalidate()
        durationTimer = nil
        
        // 重置波形为平静状态
        withAnimation(.easeOut(duration: 1.0)) {
            waveformHeights = Array(repeating: 2, count: 80)
        }
    }
    
    // 处理真实音频数据的波形更新
    private func updateWaveformWithAudioData(_ audioLevel: Float) {
        // 将音频级别转换为波形高度 (0-60像素范围，更细腻的变化)
        let normalizedLevel = min(max(audioLevel, 0.0), 1.0)
        let baseHeight = CGFloat(2 + normalizedLevel * 58) // 2-60像素范围
        
        // 添加轻微的自然变化
        let variation = CGFloat.random(in: 0.95...1.05)
        let newHeight = max(2, min(60, baseHeight * variation))
        
        // 使用快速平滑动画更新波形（滚动效果）
        withAnimation(.easeInOut(duration: 0.05)) {
            waveformHeights.removeFirst()
            waveformHeights.append(newHeight)
        }
        
        // 减少日志输出，只在显著音频活动时记录
        if audioLevel > 0.15 {
            print("🌊 音频级别: \(String(format: "%.2f", audioLevel)), 波形高度: \(String(format: "%.1f", newHeight))")
        }
    }
}

