import SwiftUI
import AVFoundation
import Combine

// 简化的录制波形显示组件
struct SimpleWaveformView: View {
    @StateObject private var audioAnalyzer = SimpleAudioAnalyzer()
    
    private let barCount = 40 // 显示40个音频条
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 3
    private let maxBarHeight: CGFloat = 30
    
    var body: some View {
        VStack(spacing: 8) {
            // 波形显示
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(for: index))
                        .frame(width: 2.5, height: barHeight(for: index))
                        .animation(.easeInOut(duration: 0.1), value: audioAnalyzer.amplitudes)
                }
            }
            .frame(height: maxBarHeight)
            
            // 音量显示
            Text("🎙️ 音量: \(Int(audioAnalyzer.currentVolume * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .onAppear {
            audioAnalyzer.startSimulation()
        }
        .onDisappear {
            audioAnalyzer.stopSimulation()
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let amplitudeIndex = min(index, audioAnalyzer.amplitudes.count - 1)
        let amplitude = audioAnalyzer.amplitudes[amplitudeIndex]
        return minBarHeight + (maxBarHeight - minBarHeight) * amplitude
    }
    
    private func barColor(for index: Int) -> Color {
        let amplitude = audioAnalyzer.amplitudes[min(index, audioAnalyzer.amplitudes.count - 1)]
        
        if amplitude > 0.7 {
            return .red.opacity(0.8)
        } else if amplitude > 0.4 {
            return .orange.opacity(0.8)
        } else if amplitude > 0.2 {
            return .green.opacity(0.8)
        } else {
            return .gray.opacity(0.6)
        }
    }
}

// 简化的音频分析器 - 用于演示
class SimpleAudioAnalyzer: ObservableObject {
    @Published var amplitudes: [CGFloat] = Array(repeating: 0.0, count: 40)
    @Published var currentVolume: CGFloat = 0.0
    
    private var timer: Timer?
    private var animationPhase: Double = 0
    
    func startSimulation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateSimulatedAmplitudes()
        }
    }
    
    func stopSimulation() {
        timer?.invalidate()
        timer = nil
        
        // 重置为静默状态
        amplitudes = Array(repeating: 0.0, count: 40)
        currentVolume = 0.0
    }
    
    private func updateSimulatedAmplitudes() {
        animationPhase += 0.2
        
        var newAmplitudes: [CGFloat] = []
        
        for i in 0..<40 {
            // 创建波形效果
            let frequency = Double(i) * 0.3 + animationPhase
            let baseAmplitude = (sin(frequency) + 1) / 2 // 0-1范围
            
            // 添加一些随机性
            let randomFactor = Double.random(in: 0.7...1.3)
            let amplitude = CGFloat(baseAmplitude * randomFactor * 0.8)
            
            newAmplitudes.append(max(0, min(1, amplitude)))
        }
        
        amplitudes = newAmplitudes
        
        // 计算平均音量
        currentVolume = amplitudes.reduce(0, +) / CGFloat(amplitudes.count)
    }
    
    // 真实的音频分析方法 - 供实际录制时使用
    func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        
        let rms = calculateRMS(samples)
        
        DispatchQueue.main.async {
            // 停止模拟，使用真实数据
            self.timer?.invalidate()
            self.timer = nil
            
            // 更新波形
            self.updateWaveformWithRealData(rms: rms)
        }
    }
    
    private func updateWaveformWithRealData(rms: Float) {
        // 移除最左边的数据，添加新数据到右边
        amplitudes.removeFirst()
        amplitudes.append(CGFloat(rms))
        
        currentVolume = CGFloat(rms)
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sum / Float(samples.count))
        
        // 归一化
        let normalizedRMS = min(rms * 10, 1.0)
        return pow(normalizedRMS, 0.4)
    }
}

#Preview {
    SimpleWaveformView()
        .padding()
        .background(.background)
} 