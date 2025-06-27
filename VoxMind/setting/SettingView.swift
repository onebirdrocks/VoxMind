import SwiftUI

struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var apiManager: APIManager
    @State private var limitlessAPIKey: String = UserDefaults.standard.string(forKey: "LimitlessAIAPIKey") ?? ""
    @State private var limitlessSaveStatus: String = ""
    @State private var showOnboarding = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal])
            Form {
                Section("主题设置") {
                    Picker("主题模式", selection: $themeManager.currentTheme) {
                        ForEach(ThemeManager.AppTheme.allCases, id: \.self) { theme in
                            Image(systemName: iconForTheme(theme))
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: themeManager.currentTheme) { _, newTheme in
                        themeManager.setTheme(newTheme)
                    }
                }
                
                Section("LLM 提供商设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Provider 选择
                        Picker("LLM 提供商", selection: $apiManager.selectedProvider) {
                            ForEach(LLMProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: apiManager.selectedProvider) { _, newProvider in
                            apiManager.setProvider(newProvider)
                        }
                        
                        // Model 选择
                        Picker("模型", selection: $apiManager.selectedModel) {
                            ForEach(apiManager.selectedProvider.supportedModels, id: \.id) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: apiManager.selectedModel) { _, newModel in
                            apiManager.setModel(newModel)
                        }
                        .id(apiManager.selectedProvider.id)
                        
                        // API Key 输入
                        let currentAPIKey = Binding<String>(
                            get: { apiManager.apiKeys[apiManager.selectedProvider.rawValue] ?? "" },
                            set: { apiManager.updateAPIKey($0, for: apiManager.selectedProvider) }
                        )
                        
                        SecureField("请输入 \(apiManager.selectedProvider.displayName) API Key", text: currentAPIKey)
                            .textFieldStyle(.roundedBorder)
                        

                        
                        // 显示当前验证状态
                        if case .none = apiManager.validationStatus {
                            // 不显示任何状态
                        } else {
                            Text(apiManager.validationStatus.message)
                                .font(.caption)
                                .foregroundColor(apiManager.validationStatus.color)
                        }
                        
                        Button {
                            Task {
                                await apiManager.validateAndSaveAPIKey()
                            }
                        } label: {
                            HStack {
                                if apiManager.isValidating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                
                                Text(getValidationButtonText())
                            }
                        }
                        .disabled(apiManager.isValidating || (apiManager.apiKeys[apiManager.selectedProvider.rawValue] ?? "").isEmpty)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                    .padding(.vertical, 4)
                }
                // 新增 Limitless.AI 设置
                Section("应用帮助") {
                    Button(action: {
                        showOnboarding = true
                    }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                            Text("查看引导教程")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
                Section("挂件 Limitless.AI 设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("请输入 Limitless.AI API Key", text: $limitlessAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Button("保存") {
                            UserDefaults.standard.set(limitlessAPIKey, forKey: "LimitlessAIAPIKey")
                            limitlessSaveStatus = "已保存"
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        if !limitlessSaveStatus.isEmpty {
                            Text(limitlessSaveStatus)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .hideKeyboardOnTap()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
    
    private func iconForTheme(_ theme: ThemeManager.AppTheme) -> String {
        switch theme {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "gear"
        }
    }
    
    private func getValidationButtonText() -> String {
        return apiManager.isValidating ? "验证中..." : "验证并保存"
    }
}



extension View {
    func hideKeyboardOnTap() -> some View {
        self.onTapGesture {
            #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
    }
}
