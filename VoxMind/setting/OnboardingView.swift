import SwiftUI
import AVFoundation
import UserNotifications

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var showPermissionRequests = false
    @State private var showQuickTips = false
    @State private var microphonePermissionGranted = false
    @State private var notificationPermissionGranted = false
    
    let totalPages = 5 // 欢迎页 + 4个功能介绍页
    
    var body: some View {
        ZStack {
            // 完全不透明的背景
            Color.white
                .ignoresSafeArea()
            
            if showPermissionRequests {
                PermissionRequestView(
                    microphoneGranted: $microphonePermissionGranted,
                    notificationGranted: $notificationPermissionGranted,
                    onComplete: {
                        showPermissionRequests = false
                        showQuickTips = true
                    }
                )
            } else if showQuickTips {
                QuickTipsView(
                    onComplete: {
                        completeOnboarding()
                    }
                )
            } else {
                // 主要 Onboarding 内容
                VStack(spacing: 0) {
                    // 跳过按钮
                    HStack {
                        Spacer()
                        if currentPage > 0 {
                            Button("跳过") {
                                showPermissionRequests = true
                            }
                            .foregroundColor(.secondary)
                            .padding()
                        }
                    }
                    
                    // 页面内容
                    TabView(selection: $currentPage) {
                        WelcomePageView()
                            .tag(0)
                        
                        FeaturePageView(
                            icon: "waveform",
                            title: "实时转录与翻译",
                            description: "任何语言实时转文字，多语言实时翻译",
                            accentColor: .blue
                        )
                        .tag(1)
                        
                        FeaturePageView(
                            icon: "brain.head.profile",
                            title: "AI 智能摘要",
                            description: "自动生成精准摘要，让笔记一目了然",
                            accentColor: .purple
                        )
                        .tag(2)
                        
                        FeaturePageView(
                            icon: "questionmark.bubble",
                            title: "智能问答与二创",
                            description: "随时回顾和创作，你的语音笔记变身知识库",
                            accentColor: .green
                        )
                        .tag(3)
                        
                        FeaturePageView(
                            icon: "lock.shield",
                            title: "隐私与安全",
                            description: "端侧处理，数据安全私密，iCloud 无缝同步",
                            accentColor: .orange
                        )
                        .tag(4)
                    }
#if os(iOS)
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
#endif
                    .animation(.easeInOut, value: currentPage)
                    
                    Spacer()
                    
                    // 底部控制区域
                    VStack(spacing: 20) {
                        // 页面指示器
                        if currentPage > 0 {
                            HStack(spacing: 8) {
                                ForEach(1..<totalPages, id: \.self) { index in
                                    Circle()
                                        .fill(currentPage == index ? Color.primary : Color.secondary.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                        .scaleEffect(currentPage == index ? 1.2 : 1.0)
                                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                                }
                            }
                        }
                        
                        // 主要按钮
                        Button(action: {
                            if currentPage == 0 {
                                withAnimation {
                                    currentPage = 1
                                }
                            } else if currentPage < totalPages - 1 {
                                withAnimation {
                                    currentPage += 1
                                }
                            } else {
                                showPermissionRequests = true
                            }
                        }) {
                            HStack {
                                Text(currentPage == 0 ? "开始体验" : (currentPage < totalPages - 1 ? "下一步" : "获取权限"))
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                if currentPage < totalPages - 1 {
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal)
                        
                        // 返回按钮（除了欢迎页）
                        if currentPage > 0 && currentPage < totalPages - 1 {
                            Button("上一步") {
                                withAnimation {
                                    currentPage -= 1
                                }
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
        dismiss()
    }
}

// MARK: - 欢迎页
struct WelcomePageView: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Logo 和应用名
            VStack(spacing: 16) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("VoxMind")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // 主标语
            VStack(spacing: 12) {
                Text("欢迎使用 VoxMind")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text("你的智能语音助手")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("让每一段语音都变成智慧")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - 功能介绍页
struct FeaturePageView: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // 功能图标
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundColor(accentColor)
            }
            
            // 功能介绍
            VStack(spacing: 16) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - 权限请求页
struct PermissionRequestView: View {
    @Binding var microphoneGranted: Bool
    @Binding var notificationGranted: Bool
    let onComplete: () -> Void
    
    @State private var currentPermission = 0
    @State private var showingPermissionAlert = false
    
    private let permissions = [
        PermissionInfo(
            icon: "mic.fill",
            title: "麦克风权限",
            description: "请允许访问麦克风，用于实时语音转录",
            color: .red
        ),
        PermissionInfo(
            icon: "bell.fill",
            title: "通知权限",
            description: "请允许通知，及时了解你的内容摘要和更新",
            color: .blue
        )
    ]
    
    var body: some View {
        ZStack {
            // 完全不透明的背景
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // 标题
                VStack(spacing: 16) {
                    Text("权限设置")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("为了提供最佳体验，VoxMind 需要以下权限")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)
                
                Spacer()
                
                // 权限列表
                VStack(spacing: 24) {
                    ForEach(0..<permissions.count, id: \.self) { index in
                        PermissionRowView(
                            permission: permissions[index],
                            isGranted: index == 0 ? microphoneGranted : notificationGranted,
                            onTap: {
                                requestPermission(at: index)
                            }
                        )
                    }
                }
                
                Spacer()
                
                // 完成按钮
                VStack(spacing: 16) {
                    Button("继续") {
                        onComplete()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                    
                    Button("稍后设置") {
                        onComplete()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 50)
            }
            .padding()
        }
    }
    
    private func requestPermission(at index: Int) {
        switch index {
        case 0: // 麦克风权限
#if os(iOS)
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    microphoneGranted = granted
                }
            }
#else
            // macOS 处理
            microphoneGranted = true
#endif
        case 1: // 通知权限
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    notificationGranted = granted
                }
            }
        default:
            break
        }
    }
}

struct PermissionInfo {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct PermissionRowView: View {
    let permission: PermissionInfo
    let isGranted: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(permission.color.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: permission.icon)
                    .font(.title3)
                    .foregroundColor(permission.color)
            }
            
            // 文本内容
            VStack(alignment: .leading, spacing: 4) {
                Text(permission.title)
                    .font(.headline)
                
                Text(permission.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // 状态/按钮
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Button("授权") {
                    onTap()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(permission.color)
                .foregroundColor(.white)
                .cornerRadius(8)
                .font(.caption)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 快速引导页
struct QuickTipsView: View {
    let onComplete: () -> Void
    @State private var currentTip = 0
    
    private let tips = [
        QuickTip(
            icon: "mic.circle.fill",
            title: "开始录音",
            description: "点击录音按钮开始录制，支持实时转录和翻译",
            color: .red
        ),
        QuickTip(
            icon: "brain.head.profile",
            title: "AI 智能摘要",
            description: "录音完成后，AI 会自动生成标题和摘要",
            color: .purple
        ),
        QuickTip(
            icon: "questionmark.bubble.fill",
            title: "智能问答",
            description: "在详情页面可以对录音内容进行问答和二创",
            color: .green
        )
    ]
    
    var body: some View {
        ZStack {
            // 完全不透明的背景
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // 标题
                VStack(spacing: 16) {
                    Text("快速上手")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("几个简单步骤，开始你的 VoxMind 之旅")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)
                
                Spacer()
                
                // 提示内容
                TabView(selection: $currentTip) {
                    ForEach(0..<tips.count, id: \.self) { index in
                        QuickTipCardView(tip: tips[index])
                            .tag(index)
                    }
                }
#if os(iOS)
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
#endif
                .frame(height: 300)
                
                // 页面指示器
                HStack(spacing: 8) {
                    ForEach(0..<tips.count, id: \.self) { index in
                        Circle()
                            .fill(currentTip == index ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentTip == index ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: currentTip)
                    }
                }
                
                Spacer()
                
                // 完成按钮
                VStack(spacing: 16) {
                    Button("开启你的 VoxMind 之旅") {
                        onComplete()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Button("稍后查看") {
                        onComplete()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 50)
            }
            .padding()
        }
    }
}

struct QuickTip {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct QuickTipCardView: View {
    let tip: QuickTip
    
    var body: some View {
        VStack(spacing: 24) {
            // 图标
            ZStack {
                Circle()
                    .fill(tip.color.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: tip.icon)
                    .font(.system(size: 40))
                    .foregroundColor(tip.color)
            }
            
            // 内容
            VStack(spacing: 12) {
                Text(tip.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(tip.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

#Preview {
    OnboardingView()
} 
