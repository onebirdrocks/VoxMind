import SwiftUI
import SwiftData
import Combine
import Foundation

// 主题管理类
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .system
    
    enum AppTheme: String, CaseIterable {
        case light = "light"
        case dark = "dark"
        case system = "system"
        
        var displayName: String {
            switch self {
            case .light: return "白天"
            case .dark: return "黑夜"
            case .system: return "系统"
            }
        }
        
        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }
    
    init() {
        // 从 UserDefaults 加载保存的主题设置
        if let savedTheme = UserDefaults.standard.string(forKey: "AppTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.currentTheme = theme
        }
    }
    
    func setTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentTheme = theme
        }
        UserDefaults.standard.set(theme.rawValue, forKey: "AppTheme")
    }
}
