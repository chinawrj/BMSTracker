//
//  WatchPowerGaugeView.swift
//  BMSTrackerWatchKit Watch App
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

/// Watch 全屏功率仪表视图
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

    var body: some View {
        GeometryReader { geo in
            let fontSize = min(geo.size.width * 0.5, geo.size.height * 0.45)
            let unitSize = fontSize * 0.22

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

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

                    Spacer()

                    // 底部：小 SoC 圆环 + V/A
                    HStack(spacing: 6) {
                        miniSocRing
                        miniLabel(String(format: "%.1fV", data.totalVoltage))
                        miniLabel(String(format: "%.1fA", data.current))
                    }
                    .padding(.bottom, 8)
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

#Preview {
    WatchPowerGaugeView(data: .preview)
}
