import SwiftUI
import SwiftData
import Speech
import Combine
import Foundation
import Translation



// API 管理类
class APIManager: ObservableObject {
    @Published var selectedProvider: LLMProvider = .openai
    @Published var selectedModel: LLMModel = LLMModel(id: "gpt-4o", displayName: "GPT-4o")
    @Published var apiKeys: [String: String] = [:]
    @Published var isValidating: Bool = false
    @Published var validationStatus: ValidationStatus = .none
    
    // 存储每个提供商的验证状态
    
    
    enum ValidationStatus {
        case none
        case valid
        case invalid(String)
        
        var message: String {
            switch self {
            case .none: return ""
            case .valid: return "API Key 验证成功"
            case .invalid(let error): return "验证失败: \(error)"
            }
        }
        
        var color: Color {
            switch self {
            case .none: return .primary
            case .valid: return .green
            case .invalid: return .red
            }
        }
    }
    
    
    
    init() {
        // 从 UserDefaults 加载保存的设置
        let defaultProvider = LLMConfig.defaultProvider()
        self.selectedProvider = defaultProvider
        self.selectedModel = LLMConfig.defaultModel(for: defaultProvider)
        
        // 加载所有Provider的API Keys
        for provider in LLMProvider.allCases {
            let key = UserDefaults.standard.string(forKey: provider.rawValue + "APIKey") ?? ""
            apiKeys[provider.rawValue] = key
        }
        
    }
    
    func validateAndSaveAPIKey(completion: (() -> Void)? = nil) {
        isValidating = true
        validationStatus = .none
        
        let currentAPIKey = apiKeys[selectedProvider.rawValue] ?? ""
        guard !currentAPIKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            isValidating = false
            validationStatus = .invalid("API Key 不能为空")
            completion?()
            return
        }
        
        print("🆕 执行验证 for \(selectedProvider.displayName)")
        
        // 构建验证请求
        let endpoint = "/models"
        guard let url = URL(string: "\(selectedProvider.baseURL)\(endpoint)") else {
            print("❌ 无效的验证 URL: \(selectedProvider.baseURL)\(endpoint)")
            isValidating = false
            validationStatus = .invalid("无效的 API 地址")
            completion?()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 设置认证头
        switch selectedProvider.rawValue {
        case "aliyun":
            request.setValue("Bearer \(currentAPIKey)", forHTTPHeaderField: "Authorization")
        case "openrouter":
            request.setValue("Bearer \(currentAPIKey)", forHTTPHeaderField: "Authorization")
            request.setValue("https://voxmind.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("VoxMind", forHTTPHeaderField: "X-Title")
            request.setValue("VoxMind/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        default:
            request.setValue("Bearer \(currentAPIKey)", forHTTPHeaderField: "Authorization")
        }
        
        print("📤 验证请求发送到: \(url)")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ 网络请求错误: \(error.localizedDescription)")
                    self.validationStatus = .invalid(error.localizedDescription)
                    self.isValidating = false
                    completion?()
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ 无效的响应类型")
                    self.validationStatus = .invalid("无效的服务器响应")
                    self.isValidating = false
                    completion?()
                    return
                }
                
                print("📥 验证响应状态码: \(httpResponse.statusCode)")
                
                // 打印响应内容以便调试
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("📄 验证响应内容: \(String(responseString.prefix(500)))...")
                }
                
                let isValid = httpResponse.statusCode == 200
                if isValid {
                    UserDefaults.standard.set(currentAPIKey, forKey: self.selectedProvider.rawValue + "APIKey")
                    self.validationStatus = .valid
                    print("✅ \(self.selectedProvider.displayName) 验证成功")
                } else {
                    self.validationStatus = .invalid("API Key 无效 (状态码: \(httpResponse.statusCode))")
                    print("❌ \(self.selectedProvider.displayName) 验证失败")
                }
                
                self.isValidating = false
                completion?()
            }
        }.resume()
    }
    
    func setProvider(_ provider: LLMProvider) {
        selectedProvider = provider
        // 确保selectedModel是新Provider支持的模型
        let newDefaultModel = LLMConfig.defaultModel(for: provider)
        selectedModel = newDefaultModel
        LLMConfig.saveSelectedProvider(provider)
        LLMConfig.saveSelectedModel(newDefaultModel, for: provider)
        validationStatus = .none
    }
    
    func setModel(_ model: LLMModel) {
        selectedModel = model
        LLMConfig.saveSelectedModel(model, for: selectedProvider)
    }
    
    func updateAPIKey(_ key: String, for provider: LLMProvider) {
        apiKeys[provider.rawValue] = key
        validationStatus = .none
    }
    
    
}

