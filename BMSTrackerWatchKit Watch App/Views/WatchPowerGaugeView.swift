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

                    // 底部小字
                    HStack(spacing: 8) {
                        miniLabel(String(format: "%.1fV", data.totalVoltage))
                        miniLabel(String(format: "%.1fA", data.current))
                        miniLabel(String(format: "%.0f%%", data.soc))
                    }
                    .padding(.bottom, 8)
                }
            }
        }
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
