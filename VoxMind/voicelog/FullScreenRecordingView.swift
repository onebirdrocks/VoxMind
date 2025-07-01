import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation
import Translation



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
    
    var body: some View {
        ZStack {
            // 背景 - 根据主题使用不同的颜色
            (themeManager.currentTheme == .dark ? Color.black : Color(.systemBackground))
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // 语言显示 - 移到顶部，更紧凑
                VStack(spacing: 4) {
                    Text("录音中...")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(themeManager.currentTheme == .dark ? .white.opacity(0.8) : .primary.opacity(0.8))
                    
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
        }
        .onDisappear {
            cleanupRecording()
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
        print("🎬 Recorder created")
        
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
                print("🎬 isRecording set to true")
            }
            
            do {
                print("🎬 Starting actual recording...")
                try await recorder.record()
                print("✅ Recording started successfully")
            } catch {
                print("❌ Recording failed: \(error)")
                await MainActor.run {
                    isRecording = false
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
                            story.chineseSummary = finalTranslatedSummary.isEmpty ? finalOriginalSummary : finalTranslatedSummary
                            print("✅ 已更新 story 的标题和摘要")
                        }
                    } else {
                        print("❌ 摘要内容为空，设置默认值")
                        await MainActor.run {
                            story.title = title
                            story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                            story.chineseSummary = story.originalSummary
                            print("🔄 已设置默认摘要")
                        }
                    }
                } else {
                    print("❌ JSON 格式不正确，无法提取 title")
                    // 设置默认值
                    await MainActor.run {
                        story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                        story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                        story.chineseSummary = story.originalSummary
                        print("🔄 已设置默认标题和摘要")
                    }
                }
            } catch {
                print("❌ JSON 解析错误: \(error)")
                // 设置默认值
                await MainActor.run {
                    story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                    story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                    story.chineseSummary = story.originalSummary
                    print("🔄 已设置默认标题和摘要")
                }
            }
            
        } catch {
            print("❌ LLM 调用失败: \(error)")
            // 设置默认值
            await MainActor.run {
                story.title = "语音记录 \(Date().formatted(.dateTime.month().day().hour().minute()))"
                story.originalSummary = String(transcriptText.prefix(100)) + (transcriptText.count > 100 ? "..." : "")
                story.chineseSummary = story.originalSummary
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
    }
}

