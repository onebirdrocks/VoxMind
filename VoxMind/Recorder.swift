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

class Recorder {
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation? = nil
    private let audioEngine: AVAudioEngine
    private let transcriber: SpokenWordTranscriber
    var playerNode: AVAudioPlayerNode?
    
    var story: Binding<Story>
    
    var file: AVAudioFile?

    private(set) var isMicAuthorized = false

    init(transcriber: SpokenWordTranscriber, story: Binding<Story>) {
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
        
        print("Setting story.url to: \(newURL.absoluteString)")
        self.story.url.wrappedValue = newURL
        print("Story.url after setting: \(story.url.wrappedValue?.absoluteString ?? "nil")")
        if !isMicAuthorized {
            await requestMicAuthorization()
            if !isMicAuthorized {
                print("Microphone access denied. Cannot record.")
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
        print("Stopping recording...")
        
        // 更优雅地停止音频引擎
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // 安全地移除tap
        do {
            audioEngine.inputNode.removeTap(onBus: 0)
        } catch {
            print("Warning: Failed to remove input tap: \(error)")
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
            print("Recording file info before closing:")
            print("  - File length: \(file.length) frames")
            print("  - File URL: \(file.url.absoluteString)")
            print("  - File exists: \(FileManager.default.fileExists(atPath: file.url.path))")
        }
        
        // Set file to nil to close it
        self.file = nil

        // Finish transcribing BEFORE setting isDone to true, so translation can still be triggered
        print("Finishing transcription before setting story.isDone...")
        try await transcriber.finishTranscribing()

        print("Setting story.isDone to true")
        story.isDone.wrappedValue = true
        print("Story.url: \(story.url.wrappedValue?.absoluteString ?? "nil")")
        
        // Check if the file exists and has content
        if let url = story.url.wrappedValue {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            print("Audio file exists at story URL: \(fileExists)")
            if fileExists {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
                    print("Audio file size: \(fileSize) bytes")
                } catch {
                    print("Failed to get file attributes: \(error)")
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
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func deactivateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        print("Audio session deactivated - microphone indicator should turn off")
    }
    #endif
    
    private func audioStream() async throws -> AsyncStream<AVAudioPCMBuffer> {
        try setupAudioEngine()
        
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        print("Input format: \(inputFormat)")
        
        // 创建格式转换器以将输入格式转换为16kHz
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                       sampleRate: 16000, 
                                       channels: 1, 
                                       interleaved: false)!
        
        print("Target format: \(targetFormat)")
        
        // 使用输入格式进行tap，然后在回调中进行格式转换
        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // 转换格式
            if let convertedBuffer = self.convertBuffer(buffer, from: inputFormat, to: targetFormat) {
                writeBufferToDisk(buffer: convertedBuffer)
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
        
        print("Creating audio file with standard 16kHz settings: \(standardSettings)")
        
        self.file = try AVAudioFile(forWriting: recordingURL, settings: standardSettings)
        print("Audio file created successfully")
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Failed to create audio converter")
            return nil
        }
        
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            print("Failed to create converted buffer")
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error {
            print("Audio conversion error: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        return convertedBuffer
    }
    
    private func writeBufferToDisk(buffer: AVAudioPCMBuffer) {
        guard let file = self.file else { return }
        do {
            try file.write(from: buffer)
        } catch {
            print("File writing error: \(error)")
        }
    }
    
    func playRecording() {
        // Use the story's URL to create a new file for reading
        guard let audioURL = story.url.wrappedValue else {
            print("Cannot play recording: no audio URL found.")
            return
        }
        
        print("Attempting to play recording from: \(audioURL.absoluteString)")
        
        // Set up audio session for playback
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 使用playAndRecord类别，这样可以避免与录制时的配置冲突
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            print("Audio session configured for playback")
        } catch {
            print("Failed to configure audio session for playback: \(error)")
        }
        #endif
        
        // Create a new audio file for reading
        let playbackFile: AVAudioFile
        do {
            playbackFile = try AVAudioFile(forReading: audioURL)
            print("Successfully opened audio file for playback with \(playbackFile.length) frames")
        } catch {
            print("Failed to open audio file for playback: \(error)")
            return
        }
        
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
        print("File format: \(fileFormat)")
        print("Output format: \(audioEngine.outputNode.inputFormat(forBus: 0))")
        
        audioEngine.connect(newPlayerNode, to: audioEngine.outputNode, format: fileFormat)
        
        newPlayerNode.scheduleFile(playbackFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
            print("Playback finished.")
            DispatchQueue.main.async {
                // Notify that playback finished if needed
            }
        }
        
        do {
            try audioEngine.start()
            newPlayerNode.play()
            print("Playback started successfully.")
        } catch {
            print("Error starting audio engine or playback: \(error)")
            
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
                print("Retrying after audio session reset...")
                
                // 重新尝试启动
                try audioEngine.start()
                
                // 重新创建播放器节点
                let retryPlayerNode = AVAudioPlayerNode()
                audioEngine.attach(retryPlayerNode)
                audioEngine.connect(retryPlayerNode, to: audioEngine.outputNode, format: fileFormat)
                retryPlayerNode.scheduleFile(playbackFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                    print("Playback finished.")
                }
                
                retryPlayerNode.play()
                self.playerNode = retryPlayerNode
                print("Retry playback started successfully.")
            } catch {
                print("Retry also failed: \(error)")
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
        print("Recorder deinit called")
        
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
        
        print("Recorder deinit completed")
    }
}
