import Foundation

// 响应数据结构
public struct TitleAndSummaryResponse {
    public let title: String
    public let originalSummary: String
    public let chineseSummary: String
    
    public init(title: String, originalSummary: String, chineseSummary: String) {
        self.title = title
        self.originalSummary = originalSummary
        self.chineseSummary = chineseSummary
    }
}

// API错误类型
public enum APIError: LocalizedError {
    case invalidURL
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case templateNotFound
    case invalidJSONResponse
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 API URL"
        case .noAPIKey:
            return "未配置 API Key"
        case .invalidResponse:
            return "API 响应格式错误"
        case .apiError(let message):
            return "API 错误: \(message)"
        case .templateNotFound:
            return "提示词模板文件未找到"
        case .invalidJSONResponse:
            return "JSON 响应格式错误"
        }
    }
}

// LLM Provider 配置
public enum LLMProvider: String, CaseIterable, Identifiable {
    case deepseek = "deepseek"
    case openai = "openai"
    case aliyun = "aliyun"
    case openrouter = "openrouter"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .aliyun: return "阿里云通义千问"
        case .openrouter: return "OpenRouter"
        }
    }
    
    public var baseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .aliyun: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        }
    }
    
    public var supportedModels: [LLMModel] {
        switch self {
        case .deepseek:
            return [
                LLMModel(id: "deepseek-chat", displayName: "DeepSeek Chat"),
                LLMModel(id: "deepseek-coder", displayName: "DeepSeek Coder")
            ]
        case .openai:
            return [
                LLMModel(id: "gpt-4o", displayName: "GPT-4o"),
                LLMModel(id: "gpt-4o-mini", displayName: "GPT-4o Mini"),
                LLMModel(id: "gpt-4-turbo", displayName: "GPT-4 Turbo"),
                LLMModel(id: "gpt-3.5-turbo", displayName: "GPT-3.5 Turbo")
            ]
        case .aliyun:
            return [
                LLMModel(id: "qwen-max", displayName: "通义千问 Max"),
                LLMModel(id: "qwen-plus", displayName: "通义千问 Plus"),
                LLMModel(id: "qwen-turbo", displayName: "通义千问 Turbo")
            ]
        case .openrouter:
            return [
                LLMModel(id: "anthropic/claude-3.5-sonnet", displayName: "Claude 3.5 Sonnet"),
                LLMModel(id: "openai/gpt-4o", displayName: "GPT-4o"),
                LLMModel(id: "google/gemini-pro-1.5", displayName: "Gemini Pro 1.5"),
                LLMModel(id: "meta-llama/llama-3.1-405b-instruct", displayName: "Llama 3.1 405B")
            ]
        }
    }
    
    public var defaultModel: LLMModel {
        return supportedModels.first!
    }
}

// LLM 模型配置
public struct LLMModel: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    
    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

// LLM 配置管理
public struct LLMConfig {
    public let provider: LLMProvider
    public let model: LLMModel
    public let apiKey: String
    
    public var apiKeyUserDefaultsKey: String {
        return "\(provider.rawValue)APIKey"
    }
    
    public static func defaultProvider() -> LLMProvider {
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedLLMProvider"),
           let provider = LLMProvider(rawValue: savedProvider) {
            return provider
        }
        return .openai // 默认使用 OpenAI
    }
    
    public static func defaultModel(for provider: LLMProvider) -> LLMModel {
        if let savedModelId = UserDefaults.standard.string(forKey: "selectedLLMModel_\(provider.rawValue)"),
           let model = provider.supportedModels.first(where: { $0.id == savedModelId }) {
            return model
        }
        return provider.defaultModel
    }
    
    public static func saveSelectedProvider(_ provider: LLMProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: "selectedLLMProvider")
    }
    
    public static func saveSelectedModel(_ model: LLMModel, for provider: LLMProvider) {
        UserDefaults.standard.set(model.id, forKey: "selectedLLMModel_\(provider.rawValue)")
    }
}

// 全局函数：生成标题和摘要
public func generateTitleAndSummary(for text: String) async throws -> TitleAndSummaryResponse {
    let selectedProvider = LLMConfig.defaultProvider()
    let selectedModel = LLMConfig.defaultModel(for: selectedProvider)
    let apiKey = UserDefaults.standard.string(forKey: selectedProvider.rawValue + "APIKey") ?? ""
    
    guard !apiKey.isEmpty else {
        throw APIError.noAPIKey
    }
    
    guard let url = URL(string: "\(selectedProvider.baseURL)/chat/completions") else {
        throw APIError.invalidURL
    }
    
    // 读取提示词模板，如果文件不存在则使用内置模板
    let template: String
    if let templatePath = Bundle.main.path(forResource: "PromptTemplate", ofType: "txt"),
       let fileTemplate = try? String(contentsOfFile: templatePath) {
        template = fileTemplate
    } else {
        // 使用内置的提示词模板
        template = """
请根据以下语音转录内容，生成标题和摘要。要求：

- 标题：简洁明了，不超过20个字，不包含引号。

- 原文摘要：用英文客观准确地总结主要内容。
  - 第一段：标题叫"总结"，然后提供一段不超过200字的总体性文字摘要。
  - 第二段：标题叫，"时间线"，然后使用清晰的 Bullet Points 呈现时间线上的主要事件和要点，按时间顺序列出，并在适当位置加入相关的 Emoji。
  - 第三段：标题叫，"重点归纳"，再次使用 Bullet Points的形式列出讨论中的核心重点和亮点，也可加入 Emoji 提高视觉美观。
  - 请确保不遗漏任何重要信息。

- 中文摘要：将原文摘要翻译成中文，确保准确流畅。

请严格按照以下 JSON 格式返回，不包含任何其他额外文字：

{
  "title": "生成的标题",
  "original_summary": "English summary of the content...",
  "chinese_summary": "中文摘要内容..."
}

语音转录内容：
{{TRANSCRIPT_TEXT}}
"""
    }
    
    // 替换模板中的占位符
    let prompt = template.replacingOccurrences(of: "{{TRANSCRIPT_TEXT}}", with: text)
    
    let requestBody: [String: Any] = [
        "model": selectedModel.id,
        "messages": [
            [
                "role": "user",
                "content": prompt
            ]
        ],
        "max_tokens": 800,
        "temperature": 0.7
    ]
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30.0  // 30秒超时
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.invalidResponse
    }
    
    guard httpResponse.statusCode == 200 else {
        throw APIError.apiError("HTTP \(httpResponse.statusCode)")
    }
    
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let message = firstChoice["message"] as? [String: Any],
          let content = message["content"] as? String else {
        throw APIError.invalidResponse
    }
    
    // 解析 JSON 响应
    guard let jsonData = content.data(using: .utf8),
          let responseJson = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let title = responseJson["title"] as? String,
          let originalSummary = responseJson["original_summary"] as? String,
          let chineseSummary = responseJson["chinese_summary"] as? String else {
        throw APIError.invalidJSONResponse
    }
    
    // 清理标题中的引号
    var cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    cleanTitle = cleanTitle.replacingOccurrences(of: "\"", with: "")
    cleanTitle = cleanTitle.replacingOccurrences(of: "'", with: "")
    cleanTitle = cleanTitle.replacingOccurrences(of: "\u{201C}", with: "")
    cleanTitle = cleanTitle.replacingOccurrences(of: "\u{201D}", with: "")
    cleanTitle = cleanTitle.replacingOccurrences(of: "\u{2018}", with: "")
    cleanTitle = cleanTitle.replacingOccurrences(of: "\u{2019}", with: "")
    cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // 确保标题不超过20字
    if cleanTitle.count > 20 {
        let index = cleanTitle.index(cleanTitle.startIndex, offsetBy: 20)
        cleanTitle = String(cleanTitle[..<index])
    }
    
    return TitleAndSummaryResponse(
        title: cleanTitle.isEmpty ? "新音频日志" : cleanTitle,
        originalSummary: originalSummary.trimmingCharacters(in: .whitespacesAndNewlines),
        chineseSummary: chineseSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    )
} 