import Foundation
import Speech
import SwiftUI
import Translation // *** Ensure correct import for Translation Framework ***
import Combine // For NotificationCenter observers
import AVFoundation
import CoreMedia

// Import Speech Analysis framework types
// These are part of the newer Speech framework APIs

// Translation specific errors
enum TranslationError: Error {
    case sessionInvalidated
    case noResult
}

// Ensure TranscriptionError is defined locally or imported.
enum TranscriptionError: Error {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case noInternetForModelDownload
    case audioFilePathNotFound
    
    var descriptionString: String {
        switch self {
        case .couldNotDownloadModel: return "Could not download the model."
        case .failedToSetupRecognitionStream: return "Could not set up the speech recognition stream."
        case .invalidAudioDataType: return "Unsupported audio format."
        case .localeNotSupported: return "This locale is not yet supported by SpeechAnalyzer."
        case .noInternetForModelDownload: return "The model could not be downloaded because the user is not connected to internet."
        case .audioFilePathNotFound: return "Couldn't write audio to file."
        }
    }
}

@Observable
final class SpokenWordTranscriber: Sendable {
    
    // MARK: - Properties
    
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    
    // The format of the audio.
    var analyzerFormat: AVAudioFormat?
    
    var converter = BufferConverter()
    var downloadProgress: Progress?
    
    // Translation using the new Translation Framework
    private var translationSession: TranslationSession?
    private var translationConfiguration: TranslationSession.Configuration?
    
    // Enum to track the status of the translation model download and readiness
    enum TranslationModelStatus: Equatable {
        case notDownloaded
        case downloading(Progress?)
        case ready
        case failed(Error)
        
        // Implement Equatable conformance
        static func == (lhs: TranslationModelStatus, rhs: TranslationModelStatus) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded):
                return true
            case (.downloading(let lhsProgress), .downloading(let rhsProgress)):
                return lhsProgress?.fractionCompleted == rhsProgress?.fractionCompleted
            case (.ready, .ready):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }
    // @Observable automatically makes this observable. No @Published needed.
    var translationModelStatus: TranslationModelStatus = .notDownloaded
    
    // Flag to prevent duplicate translation calls
    private var isTranslating = false
    
    // Track the last translated text to avoid re-translating
    private var lastTranslatedText = ""
    
    // Languages for transcription and translation
    // 动态语言设置，默认使用英语（避免不支持的语言代码）
    var transcriptionLocale = Locale(identifier: "en-US")
    // Use Locale.Language for translation
    var translationSourceLanguage: Locale.Language = .init(identifier: "en-US")
    var translationTargetLanguage: Locale.Language = .init(identifier: "zh-Hans")

    // Transcribed text storage
    var volatileTranscript: AttributedString = ""
    var finalizedTranscript: AttributedString = ""
    
    var story: Binding<VoiceLog>
    
    // MARK: - Initialization
    
    init(story: Binding<VoiceLog>) {
        self.story = story
        // Initially set to not downloaded, will be updated when translation session is available
        self.translationModelStatus = .notDownloaded
        Task {
            await setupTranslation()
        }
    }
    
    // MARK: - Reset Method
    
    func resetTranscription() {
        volatileTranscript = AttributedString("")
        finalizedTranscript = AttributedString("")
        
        // 保存现有的audioTimeRange数据
        let existingAudioTimeRangeData = story.wrappedValue.audioTimeRangeData
        
        // Reset the story's text to ensure clean state
        story.wrappedValue.text = AttributedString("")
        
        // 恢复audioTimeRange数据（如果存在）
        if let audioTimeRangeData = existingAudioTimeRangeData {
            story.wrappedValue.audioTimeRangeData = audioTimeRangeData
            print("SpokenWordTranscriber: Preserved existing audioTimeRange data during reset")
        }
        
        // Also reset translated text
        story.wrappedValue.translatedText = nil
        // Reset translation flag and tracking
        isTranslating = false
        lastTranslatedText = ""
        print("SpokenWordTranscriber: Transcription reset to clean state")
        print("Story text after reset: '\(String(story.wrappedValue.text.characters))'")
        print("Story ID: \(story.wrappedValue.id)")
    }
    
    // Method to update story binding
    func updateStoryBinding(_ newStoryBinding: Binding<VoiceLog>) {
        self.story = newStoryBinding
        print("SpokenWordTranscriber: Updated story binding to Story ID: \(newStoryBinding.wrappedValue.id)")
        // Only reset transcription for new/incomplete stories, not for completed ones
        if !newStoryBinding.wrappedValue.isDone {
            resetTranscription()
        } else {
            print("SpokenWordTranscriber: Story is completed, preserving existing transcription")
        }
    }
    
    // MARK: - Translation Setup (using Translation Framework)
    
    private func setupTranslation() async {
        // Create translation configuration
        translationConfiguration = TranslationSession.Configuration(
            source: translationSourceLanguage,
            target: translationTargetLanguage
        )
        
        // Don't set to ready here - wait for the actual translation session to be provided
        print("Translation configuration created, waiting for session...")
    }
    
    // MARK: - Transcription Setup
    
    func setUpTranscriber() async throws {
        print("🗣️ Setting up transcriber with locale: \(transcriptionLocale)")
        
        transcriber = SpeechTranscriber(locale: transcriptionLocale,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])
        
        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        
        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        do {
            try await ensureModel(transcriber: transcriber, locale: transcriptionLocale)
            print("✅ Speech recognition model loaded successfully for \(transcriptionLocale)")
        } catch let error as TranscriptionError {
            print("❌ Failed to load speech recognition model: \(error)")
            return
        }
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        print("🎤 Best available audio format: \(String(describing: analyzerFormat))")
        
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        
        guard let inputSequence else { return }
        
        recognizerTask = Task {
            do {
                for try await case let result in transcriber.results {
                    let text = result.text
                    if result.isFinal {
                        finalizedTranscript += text
                        volatileTranscript = ""
                        updateStoryWithNewText(withFinal: text)
                        
                        // 在录制过程中进行实时翻译，不需要等待URL设置
                        if !story.wrappedValue.isDone {
                            await translateFinalizedTranscript()
                        }
                        
                    } else {
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.4)
                    }
                }
            } catch {
                print("Speech recognition failed: \(error)")
                try? await finishTranscribing()
            }
        }
        
        try await analyzer?.start(inputSequence: inputSequence)
        print("Speech analyzer started.")
    }
    
    // MARK: - Audio Streaming
    
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }
        
        let convertedBuffer = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputBuilder.yield(input)
    }
    
    // MARK: - Transcription Finalization
    
    public func finishTranscribing() async throws {
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        
        print("finishTranscribing called. Story URL: \(story.wrappedValue.url?.absoluteString ?? "nil"), isDone: \(story.wrappedValue.isDone)")
        print("Final transcript before translation: '\(NSAttributedString(finalizedTranscript).string)'")

        // 在转录完成时进行最终全量翻译，覆盖之前的增量翻译
        if !story.wrappedValue.isDone {
            print("Triggering final full translation from finishTranscribing")
            await performFinalFullTranslation()
        } else {
            print("Skipping translation: story is already done")
        }
    }
    
    // MARK: - Text Update and Translation
    
    func updateStoryWithNewText(withFinal str: AttributedString) {
        // 在添加新文本之前，提取并保存 audioTimeRange 信息
        extractAndSaveAudioTimeRanges(from: str)
        story.wrappedValue.text.append(str)
    }
    
    private func extractAndSaveAudioTimeRanges(from attributedString: AttributedString) {
        // 暂时简化实现，专注于调试 audioTimeRange 属性
        print("🔍 Analyzing AttributedString with \(attributedString.runs.count) runs")
        
        var newTimeRanges: [AudioTimeRangeInfo] = []
        
        attributedString.runs.forEach { run in
            let range = run.range
            let text = String(attributedString[range].characters).prefix(30)
            print("🔍 Run text: '\(text)...'")
            
            // 尝试直接访问 audioTimeRange 属性
            if let audioTimeRange = run.audioTimeRange {
                let startSeconds = audioTimeRange.start.seconds
                let endSeconds = CMTimeAdd(audioTimeRange.start, audioTimeRange.duration).seconds
                print("   🎯 Found audioTimeRange: \(String(format: "%.2f", startSeconds))s - \(String(format: "%.2f", endSeconds))s")
                
                // 将 AttributedString 的 range 转换为 NSRange
                let nsRange = NSRange(range, in: attributedString)
                let timeRangeInfo = AudioTimeRangeInfo(
                    start: startSeconds,
                    end: endSeconds,
                    range: nsRange
                )
                
                print("   📝 Converting to AudioTimeRangeInfo: start=\(String(format: "%.2f", startSeconds))s, end=\(String(format: "%.2f", endSeconds))s, textRange=\(nsRange)")
                
                newTimeRanges.append(timeRangeInfo)
            } else {
                print("   ⚠️ No audioTimeRange found for this run")
            }
        }
        
        if !newTimeRanges.isEmpty {
            // 获取现有的时间范围数据并合并新数据
            var allTimeRanges = story.wrappedValue.getAudioTimeRanges()
            allTimeRanges.append(contentsOf: newTimeRanges)
            
            // 按开始时间排序，确保数据的一致性
            allTimeRanges.sort { $0.startSeconds < $1.startSeconds }
            
            // 使用新的方法设置数据
            story.wrappedValue.setAudioTimeRanges(allTimeRanges)
            print("   💾 Saved audioTimeRange data: \(newTimeRanges.count) new entries, \(allTimeRanges.count) total entries")
            
            // 额外的调试信息
            if allTimeRanges.count <= 5 {
                allTimeRanges.forEach { range in
                    print("      Entry: \(String(format: "%.2f", range.startSeconds))s-\(String(format: "%.2f", range.endSeconds))s, range: \(range.textRange)")
                }
            }
            
            // 验证数据是否正确保存
            let verification = story.wrappedValue.getAudioTimeRanges()
            print("   🔍 Verification: \(verification.count) entries can be loaded back")
        } else {
            print("   ⚠️ No audioTimeRange data to save")
        }
    }
    
    private func translateFinalizedTranscript() async {
        // Check if we have text to translate and translation is ready
        let textString = NSAttributedString(self.finalizedTranscript).string
        print("translateFinalizedTranscript called with text: '\(textString)'")
        print("Translation session available: \(translationSession != nil)")
        print("Translation model status: \(translationModelStatus)")
        print("Is already translating: \(isTranslating)")
        
        guard !textString.isEmpty else {
            print("No text to translate.")
            return
        }
        
        // 检查是否有新的文本需要翻译
        let newTextToTranslate: String
        if textString.hasPrefix(lastTranslatedText) {
            newTextToTranslate = String(textString.dropFirst(lastTranslatedText.count)).trimmingCharacters(in: .whitespaces)
        } else {
            newTextToTranslate = textString
        }
        
        guard !newTextToTranslate.isEmpty else {
            print("No new text to translate.")
            return
        }
        
        // Prevent duplicate translation calls
        guard !isTranslating else {
            print("Translation already in progress, skipping duplicate call.")
            return
        }
        
        // Check if translation session is still valid (not cleared by view disappearing)
        guard let session = translationSession else {
            print("Translation session not available or has been cleared.")
            return
        }
        
        isTranslating = true
        print("Starting translation of new text: '\(newTextToTranslate)'")
        
        do {
            // Additional check: verify session is still valid before using
            guard let validSession = translationSession else {
                print("Translation session became invalid during execution, aborting translation.")
                Task { @MainActor in
                    self.isTranslating = false
                }
                return
            }
            
            // Perform translation with comprehensive error handling
            let response: Any
            do {
                response = try await validSession.translate(newTextToTranslate)
                
                // Double check session is still valid after translation completes
                guard translationSession != nil else {
                    print("Translation completed but session was invalidated during operation, discarding result.")
                    Task { @MainActor in
                        self.isTranslating = false
                    }
                    return
                }
            } catch {
                // Handle TranslationSession lifecycle errors
                let errorMessage = error.localizedDescription
                if errorMessage.contains("TranslationSession after the view it was attached to has disappeared") ||
                   errorMessage.contains("text session has already been cancelled") ||
                   errorMessage.contains("CancellationError") {
                    print("Translation cancelled due to session invalidation: \(errorMessage)")
                    Task { @MainActor in
                        self.translationSession = nil
                        self.translationModelStatus = .notDownloaded
                        self.isTranslating = false
                    }
                    return
                } else {
                    throw error // Re-throw other errors to be handled by outer catch
                }
            }
            
            Task { @MainActor in
                // Extract the translated text from the response using reflection
                let mirror = Mirror(reflecting: response)
                let translatedText = mirror.children.first { $0.label == "targetText" }?.value as? String ?? ""
                print("Translation result: '\(translatedText)'")
                
                // 实时翻译：将新翻译的内容追加到现有翻译中
                if let existingTranslation = self.story.wrappedValue.translatedText {
                    let existingText = NSAttributedString(existingTranslation).string
                    let newTranslatedText = existingText + " " + translatedText
                    self.story.wrappedValue.translatedText = AttributedString(newTranslatedText)
                } else {
                    self.story.wrappedValue.translatedText = AttributedString(translatedText)
                }
                
                // 更新已翻译的文本记录
                self.lastTranslatedText = textString
                
                self.translationModelStatus = .ready
                self.isTranslating = false
                print("Translation successful. Story.translatedText updated to: '\(self.story.wrappedValue.translatedText != nil ? NSAttributedString(self.story.wrappedValue.translatedText!).string : "")'")
            }
        } catch {
            Task { @MainActor in
                let errorMessage = error.localizedDescription
                print("Translation error: \(errorMessage)")
                
                // Check if this is a TranslationSession lifecycle error
                if errorMessage.contains("TranslationSession after the view it was attached to has disappeared") {
                    print("Refusing new translation request because text session has already been cancelled")
                    // Clear the session reference to prevent further attempts
                    self.translationSession = nil
                    self.translationModelStatus = .notDownloaded
                } else {
                    // Handle other translation errors
                    // Only set to failed if we don't already have a successful translation
                    if self.story.wrappedValue.translatedText == nil || NSAttributedString(self.story.wrappedValue.translatedText!).string.isEmpty {
                        self.translationModelStatus = .failed(error)
                    } else {
                        // Keep status as ready if we already have a translation
                        self.translationModelStatus = .ready
                        print("Translation error occurred but keeping existing translation")
                    }
                }
                self.isTranslating = false
            }
        }
    }
    
    // MARK: - Final Full Translation
    
    private func performFinalFullTranslation() async {
        // 获取完整的转录文本
        let fullText = NSAttributedString(self.finalizedTranscript).string.trimmingCharacters(in: .whitespaces)
        
        print("🔄 Starting final full translation of complete text")
        print("🔄 Full text length: \(fullText.count) characters")
        print("🔄 Full text preview: '\(String(fullText.prefix(100)))...'")
        
        guard !fullText.isEmpty else {
            print("🔄 No text to translate in final translation.")
            return
        }
        
        // 检查翻译会话是否可用，如果不可用则立即退出
        // 不再等待会话重新创建，这可能导致在视图消失后的访问
        if translationSession == nil {
            print("🔄 Translation session not available, skipping final translation.")
            return
        }
        
        guard let session = translationSession else {
            print("🔄 Translation session still not available after waiting, skipping final translation.")
            return
        }
        
        // 防止重复翻译
        guard !isTranslating else {
            print("🔄 Translation already in progress, skipping final translation.")
            return
        }
        
        isTranslating = true
        print("🔄 Starting final full translation...")
        
        do {
            // Additional check: verify session is still valid before using
            guard let validSession = translationSession else {
                print("🔄 Translation session became invalid during final translation, aborting.")
                Task { @MainActor in
                    self.isTranslating = false
                }
                return
            }
            
            // 进行全量翻译，带会话验证和错误处理
            let response: Any
            do {
                response = try await validSession.translate(fullText)
                
                // Double check session is still valid after translation completes
                guard translationSession != nil else {
                    print("🔄 Final translation completed but session was invalidated during operation, discarding result.")
                    Task { @MainActor in
                        self.isTranslating = false
                    }
                    return
                }
            } catch {
                // Handle TranslationSession lifecycle errors in final translation
                let errorMessage = error.localizedDescription
                if errorMessage.contains("TranslationSession after the view it was attached to has disappeared") ||
                   errorMessage.contains("text session has already been cancelled") ||
                   errorMessage.contains("CancellationError") {
                    print("🔄 Final translation cancelled due to session invalidation: \(errorMessage)")
                    Task { @MainActor in
                        self.translationSession = nil
                        self.translationModelStatus = .notDownloaded
                        self.isTranslating = false
                    }
                    return
                } else {
                    throw error // Re-throw other errors to be handled by outer catch
                }
            }
            
            Task { @MainActor in
                // Extract the translated text from the response using reflection
                let mirror = Mirror(reflecting: response)
                let fullTranslatedText = mirror.children.first { $0.label == "targetText" }?.value as? String ?? ""
                print("🔄 Final full translation completed")
                print("🔄 Translated text length: \(fullTranslatedText.count) characters")
                print("🔄 Translated text preview: '\(String(fullTranslatedText.prefix(100)))...'")
                
                // 覆盖之前的增量翻译结果
                self.story.wrappedValue.translatedText = AttributedString(fullTranslatedText)
                
                // 更新翻译状态
                self.lastTranslatedText = fullText
                self.translationModelStatus = .ready
                self.isTranslating = false
                
                print("🔄 Final translation successful. Story.translatedText updated with full translation.")
            }
        } catch {
            Task { @MainActor in
                let errorMessage = error.localizedDescription
                print("🔄 Final translation error: \(errorMessage)")
                
                // Check if this is a TranslationSession lifecycle error
                if errorMessage.contains("TranslationSession after the view it was attached to has disappeared") {
                    print("🔄 Final translation cancelled due to session invalidation")
                    // Clear the session reference to prevent further attempts
                    self.translationSession = nil
                    self.translationModelStatus = .notDownloaded
                } else {
                    // 如果最终翻译失败，保留之前的增量翻译结果
                    self.translationModelStatus = .ready
                    print("🔄 Final translation failed, keeping existing incremental translation")
                }
                self.isTranslating = false
            }
        }
    }
    
    private func setupTranslationSession() async {
        guard let configuration = translationConfiguration else { return }
        
        // TranslationSession will be provided by the view using .translationTask
        // For now, we'll mark as ready and let the UI handle the session creation
        self.translationModelStatus = .ready
    }
    
    // MARK: - Public Properties for UI
    
    var transcriptionLocaleIdentifier: String {
        transcriptionLocale.identifier
    }
    
    var translationStatusDescription: String {
        switch translationModelStatus {
        case .ready: return "Translation model: Ready."
        case .downloading(let progress): return "Translation model: Downloading (\(Int((progress?.fractionCompleted ?? 0) * 100))%)..."
        case .failed(let error): return "Translation model: Failed (\(error.localizedDescription))"
        case .notDownloaded: return "Translation model: Not downloaded."
        }
    }
    
    // Method to set translation session from view
    func setTranslationSession(_ session: TranslationSession) {
        self.translationSession = session
        self.translationModelStatus = .ready
        print("🔧 SpokenWordTranscriber: Translation session set, model is ready.")
        print("🔧 SpokenWordTranscriber: Session object: \(session)")
    }
    
    // Method to clear translation session when view disappears
    func clearTranslationSession() {
        print("🧹 Clearing translation session reference")
        
        // Immediately clear the session reference to prevent any further use
        // This must be done FIRST to prevent race conditions
        self.translationSession = nil
        self.translationModelStatus = .notDownloaded
        
        // Cancel any ongoing translation attempts
        if isTranslating {
            print("🧹 Cancelling ongoing translation")
            isTranslating = false
        }
        
        // Reset translation tracking
        lastTranslatedText = ""
        
        print("🧹 Translation session cleared successfully")
    }
    
    // Method to update language settings
    func updateLanguageSettings(sourceLanguage: String, targetLanguage: String) async {
        print("🌐 Updating language settings: \(sourceLanguage) → \(targetLanguage)")
        
        let newLocale = Locale(identifier: sourceLanguage)
        
        // 检查语音识别是否支持这个语言
        let isSupported = await supported(locale: newLocale)
        if !isSupported {
            print("⚠️ Language \(sourceLanguage) is not supported for speech recognition")
            print("⚠️ Falling back to en-US")
            transcriptionLocale = Locale(identifier: "en-US")
        } else {
            transcriptionLocale = newLocale
            print("✅ Language \(sourceLanguage) is supported for speech recognition")
        }
        
        // Update translation languages
        translationSourceLanguage = Locale.Language(identifier: sourceLanguage)
        translationTargetLanguage = Locale.Language(identifier: targetLanguage)
        
        // Update translation configuration
        translationConfiguration = TranslationSession.Configuration(
            source: translationSourceLanguage,
            target: translationTargetLanguage
        )
        
        print("🌐 Language settings updated successfully")
        print("🌐 Transcription locale: \(transcriptionLocale)")
        print("🌐 Translation: \(translationSourceLanguage) → \(translationTargetLanguage)")
    }
    
    // Method to get supported locales for UI
    func getSupportedLocales() async -> Set<String> {
        let supportedLocales = await SpeechTranscriber.supportedLocales
        return Set(supportedLocales.map { $0.identifier })
    }
    
    // Method to manually trigger translation model preparation
    func prepareTranslationModel() async {
        self.translationModelStatus = .downloading(nil)
        
        // Simulate some preparation time (in real app, this might involve actual model download)
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        if translationSession != nil {
            self.translationModelStatus = .ready
        } else {
            self.translationModelStatus = .notDownloaded
        }
    }
    
    // Method to retry translation
    func retryTranslation() async {
        print("Retrying translation...")
        
        // Check if translation session is still available
        guard translationSession != nil else {
            print("Cannot retry translation: Translation session not available")
            translationModelStatus = .notDownloaded
            return
        }
        
        isTranslating = false // Reset the flag
        translationModelStatus = .ready // Reset the status
        await translateFinalizedTranscript()
    }
    
    deinit {
        // Clean up tasks
        recognizerTask?.cancel()
    }
}

// MARK: - Model Management Extensions

extension SpokenWordTranscriber {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw TranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        } else {
            try await downloadIfNeeded(for: transcriber)
        }
    }
    
    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier }.contains(locale.identifier)
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier }.contains(locale.identifier)
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
        }
    }
    
    func deallocate() async {
        let allocated = await AssetInventory.allocatedLocales
        for locale in allocated {
            await AssetInventory.deallocate(locale: locale)
        }
    }
}
