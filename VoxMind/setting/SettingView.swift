import SwiftUI
import UIKit
import Combine

struct CustomSecureField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.roundedBorder)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit {
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
    }
}

extension View {
    func customSecureFieldStyle() -> some View {
        modifier(CustomSecureField())
    }
    
    func hideKeyboardOnTap() -> some View {
        #if os(iOS)
        return self.contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.windows.first?.endEditing(true)
            }
        #else
        return self
        #endif
    }
}

#if os(iOS)
class CustomTextFieldDelegate: NSObject, UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // 禁用表情符号和特殊字符
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/=")
        let characterSet = CharacterSet(charactersIn: string)
        return allowedCharacters.isSuperset(of: characterSet)
    }
}

struct CustomSecureTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.isSecureTextEntry = true
        textField.delegate = context.coordinator
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .done
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CustomSecureTextField
        let delegate = CustomTextFieldDelegate()
        
        init(_ parent: CustomSecureTextField) {
            self.parent = parent
            super.init()
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            return delegate.textFieldShouldReturn(textField)
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            return delegate.textField(textField, shouldChangeCharactersIn: range, replacementString: string)
        }
    }
}
#endif

struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var apiManager: APIManager
    @State private var limitlessAPIKey: String = UserDefaults.standard.string(forKey: "LimitlessAIAPIKey") ?? ""
    @State private var limitlessSaveStatus: String = ""
    @State private var showOnboarding = false
    @State private var isThemeTransitioning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal])
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    Group {
                        Section("主题设置") {
                            VStack(spacing: 12) {
                                // 主题预览指示器
                                HStack {
                                    ForEach(ThemeManager.AppTheme.allCases, id: \.self) { theme in
                                        Circle()
                                            .fill(colorForTheme(theme))
                                            .frame(width: 12, height: 12)
                                            .scaleEffect(themeManager.currentTheme == theme ? 1.2 : 1.0)
                                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: themeManager.currentTheme)
                                    }
                                    Spacer()
                                }
                                
                                Picker("主题模式", selection: $themeManager.currentTheme) {
                                    ForEach(ThemeManager.AppTheme.allCases, id: \.self) { theme in
                                        Image(systemName: iconForTheme(theme))
                                            .tag(theme)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: themeManager.currentTheme) { _, newTheme in
                                    // 添加过渡动画状态
                                    isThemeTransitioning = true
                                    
                                    // 使用动画设置主题
                                    withAnimation(.easeInOut(duration: 0.6)) {
                                        themeManager.setTheme(newTheme)
                                    }
                                    
                                    // 重置过渡状态
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        isThemeTransitioning = false
                                    }
                                    
                                    // 强制界面刷新
                                    DispatchQueue.main.async {
                                        themeManager.objectWillChange.send()
                                    }
                                }
                                .disabled(isThemeTransitioning)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                        .overlay(
                            // 添加过渡时的微妙视觉反馈
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor.opacity(isThemeTransitioning ? 0.3 : 0), lineWidth: 2)
                                .animation(.easeInOut(duration: 0.3), value: isThemeTransitioning)
                        )
                        .cornerRadius(10)
                        .scaleEffect(isThemeTransitioning ? 0.98 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: isThemeTransitioning)
                        
                        Section("LLM 提供商设置") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("LLM 提供商", selection: $apiManager.selectedProvider) {
                                    ForEach(LLMProvider.allCases) { provider in
                                        Text(provider.displayName).tag(provider)
                                    }
                                }
                                .pickerStyle(.menu)
                                
                                Picker("模型", selection: $apiManager.selectedModel) {
                                    ForEach(apiManager.selectedProvider.supportedModels, id: \.id) { model in
                                        Text(model.displayName).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                                
                                let currentAPIKey = Binding<String>(
                                    get: { apiManager.apiKeys[apiManager.selectedProvider.rawValue] ?? "" },
                                    set: { apiManager.updateAPIKey($0, for: apiManager.selectedProvider) }
                                )
                                
                                #if os(iOS)
                                CustomSecureTextField(text: currentAPIKey, placeholder: "请输入 \(apiManager.selectedProvider.displayName) API Key")
                                    .frame(height: 40)
                                #else
                                SecureField("请输入 \(apiManager.selectedProvider.displayName) API Key", text: currentAPIKey)
                                    .customSecureFieldStyle()
                                #endif
                                
                                if case .none = apiManager.validationStatus {
                                    // 不显示任何状态
                                } else {
                                    Text(apiManager.validationStatus.message)
                                        .font(.caption)
                                        .foregroundColor(apiManager.validationStatus.color)
                                }
                                
                                Button {
                                    apiManager.validateAndSaveAPIKey()
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                        
                        Section("挂件 Limitless.AI 设置") {
                            VStack(alignment: .leading, spacing: 12) {
                                #if os(iOS)
                                CustomSecureTextField(text: $limitlessAPIKey, placeholder: "请输入 Limitless.AI API Key")
                                    .frame(height: 40)
                                #else
                                SecureField("请输入 Limitless.AI API Key", text: $limitlessAPIKey)
                                    .customSecureFieldStyle()
                                #endif
                                
                                Button(action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        UserDefaults.standard.set(limitlessAPIKey, forKey: "LimitlessAIAPIKey")
                                        limitlessSaveStatus = "✅ 已保存"
                                    }
                                    
                                    // 3秒后清除状态文本
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            limitlessSaveStatus = ""
                                        }
                                    }
                                }) {
                                    Text("保存")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(limitlessAPIKey.isEmpty)
                                .scaleEffect(limitlessAPIKey.isEmpty ? 0.95 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: limitlessAPIKey.isEmpty)
                                
                                if !limitlessSaveStatus.isEmpty {
                                    Text(limitlessSaveStatus)
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .transition(.asymmetric(
                                            insertion: .scale.combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: limitlessSaveStatus)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                        
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .animation(.easeInOut(duration: 0.5).delay(0.1), value: themeManager.currentTheme)
                }
            }
            .simultaneousGesture(DragGesture().onChanged { _ in
                #if os(iOS)
                UIApplication.shared.windows.first?.endEditing(true)
                #endif
            })
            .scrollDismissesKeyboard(.immediately)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            UIApplication.shared.windows.first?.endEditing(true)
            #endif
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
    
    private func colorForTheme(_ theme: ThemeManager.AppTheme) -> Color {
        switch theme {
        case .light: return .orange
        case .dark: return .purple
        case .system: return .blue
        }
    }
    
    private func getValidationButtonText() -> String {
        return apiManager.isValidating ? "验证中..." : "验证并保存"
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
