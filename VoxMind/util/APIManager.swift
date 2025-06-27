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
    
    func validateAndSaveAPIKey() async {
        await MainActor.run {
            isValidating = true
            validationStatus = .none
        }
        
        let currentAPIKey = apiKeys[selectedProvider.rawValue] ?? ""
        guard !currentAPIKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                isValidating = false
                validationStatus = .invalid("API Key 不能为空")
            }
            return
        }
        
        print("🆕 执行验证 for \(selectedProvider.displayName)")
        
        do {
            let isValid = try await validateAPIKey(currentAPIKey, for: selectedProvider)
            await MainActor.run {
                if isValid {
                    UserDefaults.standard.set(currentAPIKey, forKey: selectedProvider.rawValue + "APIKey")
                    validationStatus = .valid
                } else {
                    validationStatus = .invalid("API Key 无效")
                }
                isValidating = false
            }
        } catch {
            await MainActor.run {
                let errorMessage = error.localizedDescription
                validationStatus = .invalid(errorMessage)
                isValidating = false
            }
        }
    }
    
    private func validateAPIKey(_ apiKey: String, for provider: LLMProvider) async throws -> Bool {
        print("🔍 开始验证 \(provider.displayName) API Key...")
        print("🔑 Key 长度: \(apiKey.count)")
        print("🔑 Key 前缀: \(String(apiKey.prefix(10)))...")
        
        // 针对不同提供商使用不同的验证方式
        let endpoint: String
        
        switch provider.rawValue {
        case "openrouter":
            endpoint = "/models"  // OpenRouter 使用 models 端点验证
        case "aliyun":
            endpoint = "/models"  // 阿里云通义千问使用 models 端点
        default:
            endpoint = "/models"  // 默认使用 models 端点
        }
        
        guard let url = URL(string: "\(provider.baseURL)\(endpoint)") else {
            print("❌ 无效的验证 URL: \(provider.baseURL)\(endpoint)")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 根据不同提供商设置认证方式
        switch provider.rawValue {
        case "aliyun":
            // 阿里云使用 Authorization: Bearer API_KEY
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case "openrouter":
            // OpenRouter 使用标准 Bearer 认证加特殊头部
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("https://voxmind.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("VoxMind", forHTTPHeaderField: "X-Title")
            request.setValue("VoxMind/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        default:
            // 其他提供商使用标准 Bearer 认证
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        print("📤 验证请求发送到: \(url)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
                print("📥 验证响应状态码: \(httpResponse.statusCode)")
                
                // 打印响应内容以便调试
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 验证响应内容: \(String(responseString.prefix(500)))...")
                }
                
                // 根据不同提供商判断成功状态
                switch provider.rawValue {
                case "openrouter":
                    if httpResponse.statusCode == 200 {
                        // 检查响应是否包含模型列表
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let dataArray = json["data"] as? [[String: Any]],
                           !dataArray.isEmpty {
                            print("✅ OpenRouter 验证成功，找到 \(dataArray.count) 个模型")
                            return true
                        } else {
                            print("⚠️ OpenRouter 返回 200 但没有模型数据")
                            return false
                        }
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ OpenRouter API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ OpenRouter 验证失败，状态码: \(httpResponse.statusCode)")
        return false
                    }
                    
                case "aliyun":
                    if httpResponse.statusCode == 200 {
                        print("✅ 阿里云通义千问验证成功")
                        return true
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ 阿里云 API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ 阿里云验证失败，状态码: \(httpResponse.statusCode)")
                        return false
                    }
                    
                case "deepseek":
                    if httpResponse.statusCode == 200 {
                        print("✅ DeepSeek 验证成功")
                        return true
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ DeepSeek API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ DeepSeek 验证失败，状态码: \(httpResponse.statusCode)")
                        return false
                    }
                    
                default:
                    // 其他提供商的通用验证
                    if httpResponse.statusCode == 200 {
                        print("✅ \(provider.displayName) 验证成功")
                        return true
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ \(provider.displayName) API Key 无效或无权限")
                        return false
                    } else {
                        print("❌ \(provider.displayName) 验证失败，状态码: \(httpResponse.statusCode)")
                        return false
                    }
                }
            }
            
            print("❌ 无法获取 HTTP 响应")
            return false
            
        } catch {
            print("❌ 验证请求失败: \(error.localizedDescription)")
            
            // 网络错误可能不代表 API Key 无效
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                    throw APIError.apiError("网络连接问题，请检查网络设置")
                default:
                    throw APIError.apiError("网络请求失败: \(urlError.localizedDescription)")
                }
            }
            
            throw error
        }
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

