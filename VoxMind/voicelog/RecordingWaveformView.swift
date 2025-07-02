import SwiftUI
import AVFoundation
import Combine

// 实时录制波形显示组件
struct RecordingWaveformView: View {
    @ObservedObject var audioAnalyzer: RecordingAudioAnalyzer
    
    private let barCount = 60 // 显示60个音频条
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 3
    private let maxBarHeight: CGFloat = 40
    
    var body: some View {
        VStack(spacing: 8) {
            // 波形显示
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index))
                        .frame(width: 3, height: barHeight(for: index))
                        .animation(.easeInOut(duration: 0.1), value: audioAnalyzer.amplitudes)
                }
            }
            .frame(height: maxBarHeight)
            
            // 当前音量指示
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text("音量: \(Int(audioAnalyzer.currentVolume * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let amplitudeIndex = min(index, audioAnalyzer.amplitudes.count - 1)
        let amplitude = audioAnalyzer.amplitudes[amplitudeIndex]
        return minBarHeight + (maxBarHeight - minBarHeight) * amplitude
    }
    
    private func barColor(for index: Int) -> Color {
        let amplitude = audioAnalyzer.amplitudes[min(index, audioAnalyzer.amplitudes.count - 1)]
        
        // 根据振幅显示不同颜色
        if amplitude > 0.7 {
            return .red.opacity(0.8) // 高音量 - 红色
        } else if amplitude > 0.3 {
            return .orange.opacity(0.8) // 中音量 - 橙色
        } else if amplitude > 0.1 {
            return .green.opacity(0.8) // 正常音量 - 绿色
        } else {
            return .gray.opacity(0.6) // 低音量 - 灰色
        }
    }
}

// 实时录制音频分析器
@MainActor
class RecordingAudioAnalyzer: ObservableObject {
    @Published var amplitudes: [CGFloat] = Array(repeating: 0.0, count: 60)
    @Published var currentVolume: CGFloat = 0.0
    
    private let smoothingFactor: Float = 0.3
    private var smoothedAmplitudes: [Float] = Array(repeating: 0.0, count: 60)
    
    // 分析实时音频缓冲区
    nonisolated func analyzeRealtimeAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        
        // 计算当前缓冲区的RMS值
        let rms = calculateRMS(samples)
        
        // 更新波形数据 - 将新数据从右侧推入，左侧移出
        updateWaveformAmplitudes(with: rms)
    }
    
    private nonisolated func updateWaveformAmplitudes(with newAmplitude: Float) {
        Task { @MainActor in
            // 移除最左边的数据，添加新数据到右边
            smoothedAmplitudes.removeFirst()
            
            // 应用平滑处理
            let smoothedValue = smoothedAmplitudes.last! * (1 - smoothingFactor) + newAmplitude * smoothingFactor
            smoothedAmplitudes.append(smoothedValue)
            
            // 更新UI
            self.amplitudes = self.smoothedAmplitudes.map { CGFloat($0) }
            self.currentVolume = CGFloat(newAmplitude)
        }
    }
    
    private nonisolated func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sum / Float(samples.count))
        
        // 归一化到 0-1 范围，并应用对数缩放以提高可视化效果
        let normalizedRMS = min(rms * 15, 1.0) // 放大并限制在1.0以内
        return pow(normalizedRMS, 0.4) // 调整缩放，使变化更明显
    }
    
    // 重置波形数据
    func reset() {
        Task { @MainActor in
            self.amplitudes = Array(repeating: 0.0, count: 60)
            self.currentVolume = 0.0
            self.smoothedAmplitudes = Array(repeating: 0.0, count: 60)
        }
    }
} 
