import Foundation
import AVFoundation
import SwiftUI
import SwiftData
import Speech
import CoreMedia

// 用于保存 audioTimeRange 信息的结构体
struct AudioTimeRangeInfo: Codable {
    let startSeconds: Double
    let endSeconds: Double
    let textRange: NSRange
    
    init(start: Double, end: Double, range: NSRange) {
        self.startSeconds = start
        self.endSeconds = end
        self.textRange = range
    }
}

@Model
class VoiceLog: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var textData: Data // Store AttributedString as Data
    var translatedTextData: Data? // Store AttributedString as Data
    var audioTimeRangeData: Data? // Store audioTimeRange information
    var originalSummary: String?
    var translatedSummary: String?
    var audioFileName: String? // Store filename instead of full URL
    var isDone: Bool
    
    // 缓存解码后的时间范围数据，避免频繁JSON解码
    private var _cachedAudioTimeRanges: [AudioTimeRangeInfo]?
    private var _cacheDataHash: Data?
    
    // 缓存解码后的主文本，避免频繁解码
    private var _cachedText: AttributedString?
    private var _textDataHash: Data?
    
    // Computed properties for AttributedString access
    var text: AttributedString {
        get {
            // 检查缓存是否有效
            if let cached = _cachedText,
               let cachedHash = _textDataHash,
               cachedHash == textData {
                return cached
            }
            
            guard let attributedString = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: textData) else {
                let result = AttributedString("")
                // 更新缓存
                _cachedText = result
                _textDataHash = textData
                return result
            }
            
            let result = AttributedString(attributedString)
            
            // 更新缓存
            _cachedText = result
            _textDataHash = textData
            
            return result
        }
        set {
            // 保存基本的 AttributedString
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: NSAttributedString(newValue), requiringSecureCoding: false) {
                textData = data
                // 清除缓存
                _cachedText = nil
                _textDataHash = nil
            }
            
            // 不要在这里清空audioTimeRangeData，让SpokenWordTranscriber直接管理
            // audioTimeRange数据应该由转录器在适当的时候设置和更新
        }
    }
    
    // 获取保存的时间范围信息（带缓存优化）
    func getAudioTimeRanges() -> [AudioTimeRangeInfo] {
        guard let timeRangeData = audioTimeRangeData else {
    #if DEBUG
            print("📱 getAudioTimeRanges: No audioTimeRangeData found")
            #endif
            return []
        }
        
        // 检查缓存是否有效
        if let cached = _cachedAudioTimeRanges, 
           let cachedHash = _cacheDataHash,
           cachedHash == timeRangeData {
            // 减少缓存使用的打印频率，避免播放时过度输出
            return cached
        }
        
        // 解码数据并更新缓存
        guard let timeRanges = try? JSONDecoder().decode([AudioTimeRangeInfo].self, from: timeRangeData) else {
    #if DEBUG
            print("📱 getAudioTimeRanges: Failed to decode audioTimeRangeData")
            #endif
            return []
        }
        
#if DEBUG
        print("📱 getAudioTimeRanges: Successfully decoded \(timeRanges.count) entries from storage")
        #endif
        
        // 只在调试模式下输出详细信息，减少性能影响
        #if DEBUG
        if timeRanges.count <= 5 {
            timeRanges.enumerated().forEach { index, range in
                print("   📱 Entry \(index): start=\(String(format: "%.2f", range.startSeconds))s, end=\(String(format: "%.2f", range.endSeconds))s, textRange=\(range.textRange)")
            }
        } else {
            // 对于大量数据，只打印前2个条目
            timeRanges.prefix(2).enumerated().forEach { index, range in
                print("   📱 Entry \(index): start=\(String(format: "%.2f", range.startSeconds))s, end=\(String(format: "%.2f", range.endSeconds))s, textRange=\(range.textRange)")
            }
            print("   📱 ... and \(timeRanges.count - 2) more entries")
        }
        #endif
        
        // 更新缓存
        _cachedAudioTimeRanges = timeRanges
        _cacheDataHash = timeRangeData
        
        return timeRanges
    }
    
    // 设置audioTimeRange数据并清除缓存
    func setAudioTimeRanges(_ timeRanges: [AudioTimeRangeInfo]) {
        #if DEBUG
        print("💾 setAudioTimeRanges: Attempting to save \(timeRanges.count) entries")
        
        // 只在调试模式下打印详细信息，减少性能影响
        if timeRanges.count <= 5 {
            timeRanges.enumerated().forEach { index, range in
                print("   💾 Saving Entry \(index): start=\(String(format: "%.2f", range.startSeconds))s, end=\(String(format: "%.2f", range.endSeconds))s, textRange=\(range.textRange)")
            }
        } else {
            // 对于大量数据，只打印前2个条目
            timeRanges.prefix(2).enumerated().forEach { index, range in
                print("   💾 Saving Entry \(index): start=\(String(format: "%.2f", range.startSeconds))s, end=\(String(format: "%.2f", range.endSeconds))s, textRange=\(range.textRange)")
            }
            print("   💾 ... and \(timeRanges.count - 2) more entries to save")
        }
        #endif
        
        if let data = try? JSONEncoder().encode(timeRanges) {
            audioTimeRangeData = data
            // 清除缓存，强制重新加载
            _cachedAudioTimeRanges = nil
            _cacheDataHash = nil
            
            #if DEBUG
            print("💾 setAudioTimeRanges: Successfully encoded and saved \(timeRanges.count) entries (data size: \(data.count) bytes)")
            
            // 立即验证保存是否成功
            let verification = getAudioTimeRanges()
            if verification.count == timeRanges.count {
                print("💾 setAudioTimeRanges: ✅ Verification successful - \(verification.count) entries can be retrieved")
            } else {
                print("💾 setAudioTimeRanges: ❌ Verification failed - expected \(timeRanges.count) entries, got \(verification.count)")
            }
            #endif
        } else {
            #if DEBUG
            print("💾 setAudioTimeRanges: ❌ Failed to encode audioTimeRange data")
            #endif
        }
    }
    
    // 缓存解码后的翻译文本，避免频繁解码
    private var _cachedTranslatedText: AttributedString?
    private var _translatedTextDataHash: Data?
    
    var translatedText: AttributedString? {
        get {
            guard let data = translatedTextData else { return nil }
            
            // 检查缓存是否有效
            if let cached = _cachedTranslatedText,
               let cachedHash = _translatedTextDataHash,
               cachedHash == data {
                return cached
            }
            
            // 解码数据并更新缓存
            guard let attributedString = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) else {
                return nil
            }
            
            let result = AttributedString(attributedString)
            
            // 更新缓存
            _cachedTranslatedText = result
            _translatedTextDataHash = data
            
            return result
        }
        set {
            if let newValue = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: NSAttributedString(newValue), requiringSecureCoding: false) {
                translatedTextData = data
                // 清除缓存
                _cachedTranslatedText = nil
                _translatedTextDataHash = nil
            } else {
                translatedTextData = nil
                _cachedTranslatedText = nil
                _translatedTextDataHash = nil
            }
        }
    }
    
    var url: URL? {
        get {
            guard let fileName = audioFileName else { return nil }
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documentsPath.appendingPathComponent(fileName)
        }
        set {
            if let newURL = newValue {
                audioFileName = newURL.lastPathComponent
                // 确保文件在Documents目录中
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let targetURL = documentsPath.appendingPathComponent(newURL.lastPathComponent)
                if newURL != targetURL && FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.copyItem(at: newURL, to: targetURL)
                }
            } else {
                audioFileName = nil
            }
        }
    }

    init(title: String, text: AttributedString, translatedText: AttributedString? = nil, originalSummary: String? = nil, chineseSummary: String? = nil, url: URL? = nil, isDone: Bool = false) {
        self.id = UUID()
        self.title = title
        self.originalSummary = originalSummary
        self.translatedSummary = chineseSummary
        self.isDone = isDone
        
        // Initialize stored properties first
        if let textData = try? NSKeyedArchiver.archivedData(withRootObject: NSAttributedString(text), requiringSecureCoding: false) {
            self.textData = textData
        } else {
            self.textData = Data()
        }
        
        if let translatedText = translatedText,
           let translatedData = try? NSKeyedArchiver.archivedData(withRootObject: NSAttributedString(translatedText), requiringSecureCoding: false) {
            self.translatedTextData = translatedData
        } else {
            self.translatedTextData = nil
        }
        
        if let url = url {
            self.audioFileName = url.lastPathComponent
            // 确保文件在Documents目录中
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let targetURL = documentsPath.appendingPathComponent(url.lastPathComponent)
            if url != targetURL && FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.copyItem(at: url, to: targetURL)
            }
        } else {
            self.audioFileName = nil
        }
    }

    static func blank() -> VoiceLog {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        let timestamp = formatter.string(from: Date())
        let title = "新音频日志\(timestamp)"
        let story = VoiceLog(title: title, text: AttributedString(""), isDone: false)
        print("Created blank story: title=\(story.title), isDone=\(story.isDone), text.isEmpty=\(String(story.text.characters).isEmpty)")
        return story
    }

    // Temporarily removed suggestedTitle() due to potential dependency issues.
    /*
    func suggestedTitle() async throws -> String? { ... }
    */
    
    // MARK: - AttributedString Formatting for Display
    
    func storyBrokenUpByLines() -> AttributedString {
        // 移除调试打印，避免播放时频繁打印
        if url == nil {
            return text
        } else {
            var final = AttributedString("")
            var working = AttributedString("")
            let copy = text
            copy.runs.forEach { run in
                if copy[run.range].characters.contains(".") {
                    working.append(copy[run.range])
                    final.append(working)
                    final.append(AttributedString("\n\n"))
                    working = AttributedString("")
                } else {
                    if working.characters.isEmpty {
                        let newText = copy[run.range].characters
                        let attributes = run.attributes
                        let trimmed = newText.trimmingPrefix(" ")
                        let newAttributed = AttributedString(trimmed, attributes: attributes)
                        working.append(newAttributed)
                    } else {
                        working.append(copy[run.range])
                    }
                }
            }
            
            if final.characters.isEmpty {
                return working
            }
            
            return final
        }
    }
    
    func getTextToDisplay() -> AttributedString {
        if isDone, let translatedText = translatedText, !NSAttributedString(translatedText).string.isEmpty {
            return translatedText
        }
        return text
    }
}

extension VoiceLog: Equatable, Hashable {
    static func == (lhs: VoiceLog, rhs: VoiceLog) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
