//
//  WatchPowerGaugeView.swift
//  BMSTrackerWatchKit Watch App
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

/// Watch 全屏功率仪表视图
/// 带跑道形 C-rate 指示环（2C 满格）
struct WatchPowerGaugeView: View {
    let data: BMSData

    private var power: Double {
        data.totalVoltage * data.current
    }

    private var absPower: Double {
        abs(power)
    }

    private var powerText: String {
        String(format: "%.0f", absPower)
    }

    private var powerLabel: String {
        if power > 0.1 { return "CHG" }
        if power < -0.1 { return "DSG" }
        return "STBY"
    }

    private var powerColor: Color {
        if power > 0.1 { return .green }
        if power < -0.1 { return .orange }
        return .gray
    }

    /// 电流与 2C 的比率 (0~1)
    private var cRate: Double {
        guard data.fullChargeCapacity > 0 else { return 0 }
        return min(abs(data.current) / (data.fullChargeCapacity * 2), 1.0)
    }

    /// C-rate 颜色（与 iOS 锁屏一致）
    private var cRateColor: Color {
        if cRate > 0.5 { return .red }      // >1C
        if cRate > 0.25 { return .orange }   // >0.5C
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            let fontSize = min(geo.size.width * 0.45, geo.size.height * 0.38)
            let unitSize = fontSize * 0.22
            let trackWidth: CGFloat = 6
            let trackInset: CGFloat = 4
            let cornerRadius = min(geo.size.width, geo.size.height) * 0.3

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 8) {
                    // 功率区域（被跑道框住）
                    ZStack {
                        // 跑道背景轨道
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: trackWidth)

                        // 跑道 C-rate 填充
                        StadiumTrack(progress: cRate, cornerRadius: cornerRadius)
                            .stroke(cRateColor, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                            .animation(.easeInOut(duration: 0.4), value: cRate)

                        VStack(spacing: 2) {
                            // 状态标签
                            Text(powerLabel)
                                .font(.system(size: fontSize * 0.1, weight: .medium, design: .monospaced))
                                .foregroundStyle(powerColor.opacity(0.6))
                                .tracking(2)

                            // 超大功率值
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(powerText)
                                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                    .foregroundStyle(powerColor)
                                    .minimumScaleFactor(0.4)
                                    .lineLimit(1)
                                Text("W")
                                    .font(.system(size: unitSize, weight: .medium, design: .rounded))
                                    .foregroundStyle(powerColor.opacity(0.5))
                            }
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: powerText)

                            // C-rate 数值
                            Text(String(format: "%.2fC", data.fullChargeCapacity > 0
                                        ? abs(data.current) / data.fullChargeCapacity : 0))
                                .font(.system(size: fontSize * 0.12, design: .monospaced))
                                .foregroundStyle(cRateColor.opacity(0.7))
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, trackInset)

                    // 底部：小 SoC 圆环 + V/A（跑道外面）
                    HStack(spacing: 6) {
                        miniSocRing
                        miniLabel(String(format: "%.1fV", data.totalVoltage))
                        miniLabel(String(format: "%.1fA", data.current))
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    /// 小型 SoC 圆环
    private var miniSocRing: some View {
        let size: CGFloat = 20
        let lineWidth: CGFloat = 2.5
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(data.soc / 100.0))
                .stroke(socRingColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.0f", data.soc))
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: size, height: size)
    }

    private var socRingColor: Color {
        if data.soc > 60 { return .green }
        if data.soc > 20 { return .orange }
        return .red
    }

    private func miniLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
    }
}

// MARK: - 跑道形 Shape（圆角矩形描边进度）

/// 沿圆角矩形（跑道形）路径绘制部分描边
struct StadiumTrack: Shape {
    var progress: Double
    var cornerRadius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // 完整的圆角矩形路径
        let fullPath = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: rect)

        // 计算路径总长度，截取 progress 比例
        let trimmed = fullPath.trimmedPath(from: 0, to: progress)
        return trimmed
    }
}

#Preview {
    WatchPowerGaugeView(data: .preview)
}
