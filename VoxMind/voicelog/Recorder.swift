//
//  Recorder.swift
//  OBVoiceLab
//
//  Created by Ruan Yiming on 2025/6/22.
//
import Foundation
import AVFoundation
import SwiftUI
import Speech

// 本地调试配置
private func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
    #endif
}

class Recorder {
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation? = nil
    private let audioEngine: AVAudioEngine
    private let transcriber: SpokenWordTranscriber
    var playerNode: AVAudioPlayerNode?
    
    var story: Binding<VoiceLog>
    
    var file: AVAudioFile?

    private(set) var isMicAuthorized = false
    
    // 添加音频级别回调支持  
    var audioLevelCallback: ((Float) -> Void)?

    init(transcriber: SpokenWordTranscriber, story: Binding<VoiceLog>) {
        self.audioEngine = AVAudioEngine()
        self.transcriber = transcriber
        self.story = story
    }
    
    func requestMicAuthorization() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            isMicAuthorized = true
            return
        }
        
        if status == .notDetermined {
            isMicAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            isMicAuthorized = false
        }
    }

    func record() async throws {
        // Generate a new unique URL for each recording
        let newURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(for: .wav)
        
        debugPrint("Setting story.url to: \(newURL.absoluteString)")
        self.story.url.wrappedValue = newURL
        debugPrint("Story.url after setting: \(story.url.wrappedValue?.absoluteString ?? "nil")")
        if !isMicAuthorized {
            await requestMicAuthorization()
            if !isMicAuthorized {
                debugPrint("Microphone access denied. Cannot record.")
                throw NSError(domain: "Recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied."])
            }
        }

        #if os(iOS)
        try setUpAudioSession()
        #endif

        try await transcriber.setUpTranscriber()
        
        for await inputBuffer in try await audioStream() {
            try await self.transcriber.streamAudioToTranscriber(inputBuffer)
        }
    }
    
    func stopRecording() async throws {
        debugPrint("Stopping recording...")
        
        // 更优雅地停止音频引擎
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // 安全地移除tap
        do {
            audioEngine.inputNode.removeTap(onBus: 0)
        } catch {
            debugPrint("Warning: Failed to remove input tap: \(error)")
        }
        
        // 结束输出流
        outputContinuation?.finish()
        outputContinuation = nil
        
        // 释放音频会话，确保麦克风指示器关闭
        #if os(iOS)
        try deactivateAudioSession()
        #endif

        // Close the recording file to ensure all data is written
        if let file = self.file {
            debugPrint("Recording file info before closing:")
            debugPrint("  - File length: \(file.length) frames")
            debugPrint("  - File URL: \(file.url.absoluteString)")
            debugPrint("  - File exists: \(FileManager.default.fileExists(atPath: file.url.path))")
        }
        
        // Set file to nil to close it
        self.file = nil

        // Finish transcribing BEFORE setting isDone to true, so translation can still be triggered
        debugPrint("Finishing transcription before setting story.isDone...")
        try await transcriber.finishTranscribing()

        debugPrint("Setting story.isDone to true")
        story.isDone.wrappedValue = true
        debugPrint("Story.url: \(story.url.wrappedValue?.absoluteString ?? "nil")")
        
        // Check if the file exists and has content
        if let url = story.url.wrappedValue {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            debugPrint("Audio file exists at story URL: \(fileExists)")
            if fileExists {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
                    debugPrint("Audio file size: \(fileSize) bytes")
                } catch {
                    debugPrint("Failed to get file attributes: \(error)")
                }
            }
        }

        // Commenting out suggestedTitle() call as it might depend on unavailable dependencies
        // and was causing a compile error. Restore it if SystemLanguageModel is properly available.
        /*
        Task {
            do {
                let suggestedTitle = try await story.wrappedValue.suggestedTitle()
                if let title = suggestedTitle, !title.isEmpty {
                    self.story.title.wrappedValue = title
                }
            } catch {
                print("Could not suggest title: \(error)")
            }
        }
        */
    }
    
    func pauseRecording() {
        audioEngine.pause()
    }
    
    func resumeRecording() throws {
        try audioEngine.start()
    }

    #if os(iOS)
    private func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func deactivateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        debugPrint("Audio session deactivated - microphone indicator should turn off")
    }
    #endif
    
    private func audioStream() async throws -> AsyncStream<AVAudioPCMBuffer> {
        try setupAudioEngine()
        
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        debugPrint("Input format: \(inputFormat)")
        
        // 创建格式转换器以将输入格式转换为16kHz
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                       sampleRate: 16000, 
                                       channels: 1, 
                                       interleaved: false)!
        
        debugPrint("Target format: \(targetFormat)")
        
        // 使用输入格式进行tap，然后在回调中进行格式转换
        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // 转换格式
            if let convertedBuffer = self.convertBuffer(buffer, from: inputFormat, to: targetFormat) {
                writeBufferToDisk(buffer: convertedBuffer)
                
                // 计算音频级别并回调
                let audioLevel = self.calculateAudioLevel(from: convertedBuffer)
                DispatchQueue.main.async {
                    self.audioLevelCallback?(audioLevel)
                }
                
                self.outputContinuation?.yield(convertedBuffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) { continuation in
            self.outputContinuation = continuation
        }
    }
    
    private func setupAudioEngine() throws {
        // 使用Speech框架标准的16kHz格式设置
        let standardSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        // Use the story's URL which was set in record() method
        guard let recordingURL = story.url.wrappedValue else {
            throw NSError(domain: "Recorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "No recording URL available"])
        }
        
        debugPrint("Creating audio file with standard 16kHz settings: \(standardSettings)")
        
        self.file = try AVAudioFile(forWriting: recordingURL, settings: standardSettings)
        debugPrint("Audio file created successfully")
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            debugPrint("Failed to create audio converter")
            return nil
        }
        
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            debugPrint("Failed to create converted buffer")
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error {
            debugPrint("Audio conversion error: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        return convertedBuffer
    }
    
    private func writeBufferToDisk(buffer: AVAudioPCMBuffer) {
        guard let file = self.file else { return }
        do {
            try file.write(from: buffer)
        } catch {
            debugPrint("File writing error: \(error)")
        }
    }
    
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        
        // 计算RMS (Root Mean Square)
        guard !samples.isEmpty else { return 0.0 }
        
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sum / Float(samples.count))
        
        // 归一化到 0-1 范围
        let normalizedRMS = min(rms * 10, 1.0)
        return pow(normalizedRMS, 0.4) // 平方根缩放，使小振幅更明显
    }
    
    func playRecording() {
        // Use the story's URL to create a new file for reading
        guard let audioURL = story.url.wrappedValue else {
                    debugPrint("Cannot play recording: no audio URL found.")
            return
        }
        
    debugPrint("Attempting to play recording from: \(audioURL.absoluteString)")
        
    // 异步加载音频文件，避免主线程阻塞
    Task.detached(priority: .userInitiated) {
        // Set up audio session for playback
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 使用playAndRecord类别，这样可以避免与录制时的配置冲突
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            debugPrint("Audio session configured for playback")
        } catch {
            debugPrint("Failed to configure audio session for playback: \(error)")
            return
        }
        #endif
        
        // Create a new audio file for reading
        let playbackFile: AVAudioFile
        do {
            playbackFile = try AVAudioFile(forReading: audioURL)
            debugPrint("Successfully opened audio file for playback with \(playbackFile.length) frames")
        } catch {
            debugPrint("Failed to open audio file for playback: \(error)")
            return
        }
            
            // 在主线程设置播放
            await MainActor.run {
                self.setupPlaybackOnMainThread(with: playbackFile)
            }
        }
    }
    
    @MainActor
    private func setupPlaybackOnMainThread(with playbackFile: AVAudioFile) {
        
        // Stop any existing playback more gracefully
        if let existingPlayerNode = playerNode {
            existingPlayerNode.stop()
            audioEngine.detach(existingPlayerNode)
            self.playerNode = nil
        }
        
        // 确保音频引擎完全停止
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // 重置音频引擎
        audioEngine.reset()
        
        // Create and configure new player node
        let newPlayerNode = AVAudioPlayerNode()
        self.playerNode = newPlayerNode
        
        audioEngine.attach(newPlayerNode)
        
        // 使用文件的原始格式进行播放，让音频引擎处理格式转换
        let fileFormat = playbackFile.processingFormat
        debugPrint("File format: \(fileFormat)")
        debugPrint("Output format: \(audioEngine.outputNode.inputFormat(forBus: 0))")
        
        audioEngine.connect(newPlayerNode, to: audioEngine.outputNode, format: fileFormat)
        
        newPlayerNode.scheduleFile(playbackFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
            debugPrint("Playback finished.")
            DispatchQueue.main.async {
                // Notify that playback finished if needed
            }
        }
        
        do {
            try audioEngine.start()
            newPlayerNode.play()
            debugPrint("Playback started successfully.")
        } catch {
            debugPrint("Error starting audio engine or playback: \(error)")
            
            // 清理失败的播放设置
            newPlayerNode.stop()
            audioEngine.detach(newPlayerNode)
            self.playerNode = nil
            
            // 尝试重新配置音频会话并重试一次
            #if os(iOS)
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false)
                try audioSession.setActive(true)
                DebugConfig.debugPrint("Retrying after audio session reset...")
                
                // 重新尝试启动
                try audioEngine.start()
                
                // 重新创建播放器节点
                let retryPlayerNode = AVAudioPlayerNode()
                audioEngine.attach(retryPlayerNode)
                audioEngine.connect(retryPlayerNode, to: audioEngine.outputNode, format: fileFormat)
                retryPlayerNode.scheduleFile(playbackFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                    DebugConfig.debugPrint("Playback finished.")
                }
                
                retryPlayerNode.play()
                self.playerNode = retryPlayerNode
                DebugConfig.debugPrint("Retry playback started successfully.")
            } catch {
                DebugConfig.debugPrint("Retry also failed: \(error)")
            }
            #endif
        }
    }
    
    func stopPlaying() {
        playerNode?.stop()
        audioEngine.stop()
        
        if let playerNode = playerNode {
            audioEngine.detach(playerNode)
            self.playerNode = nil
        }
        
        // 停止播放时恢复音频会话
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false)
            print("Audio session deactivated after playback")
        } catch {
            print("Failed to deactivate audio session after playback: \(error)")
        }
        #endif
    }
    
    deinit {
        debugPrint("Recorder deinit called")
        
        // 停止播放
        if let playerNode = playerNode {
            playerNode.stop()
            if audioEngine.attachedNodes.contains(playerNode) {
                audioEngine.detach(playerNode)
            }
            self.playerNode = nil
        }
        
        // 停止录制
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // 清理输出流
        outputContinuation?.finish()
        outputContinuation = nil
        
        // 清理文件引用
        file = nil
        
        debugPrint("Recorder deinit completed")
    }
}
