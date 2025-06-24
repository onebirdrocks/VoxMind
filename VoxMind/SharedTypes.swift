import Foundation

// 响应数据结构
struct TitleAndSummaryResponse {
    let title: String
    let originalSummary: String
    let chineseSummary: String
}

// API错误类型
enum APIError: LocalizedError {
    case invalidURL
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case templateNotFound
    case invalidJSONResponse
    
    var errorDescription: String? {
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

// 全局函数：生成标题和摘要
func generateTitleAndSummary(for text: String) async throws -> TitleAndSummaryResponse {
    let apiKey = UserDefaults.standard.string(forKey: "DeepSeekAPIKey") ?? ""
    guard !apiKey.isEmpty else {
        throw APIError.noAPIKey
    }
    
    guard let url = URL(string: "https://api.deepseek.com/v1/chat/completions") else {
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
        "model": "deepseek-chat",
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