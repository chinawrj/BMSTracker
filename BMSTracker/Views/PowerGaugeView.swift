//
//  PowerGaugeView.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

/// 横屏超大功率仪表视图
struct PowerGaugeView: View {
    let data: BMSData

    /// 功率 = 电压 × 电流，单位 W
    private var power: Double {
        data.totalVoltage * data.current
    }

    /// 功率绝对值
    private var absPower: Double {
        abs(power)
    }

    /// 功率显示文本，始终使用 W
    private var powerText: String {
        String(format: "%.0f", absPower)
    }

    private var powerUnit: String { "W" }

    /// 放电为负电流，显示为正功率（消耗）；充电为正电流
    private var powerLabel: String {
        if power > 0.1 {
            return "CHARGING"
        } else if power < -0.1 {
            return "DISCHARGING"
        } else {
            return "STANDBY"
        }
    }

    private var powerColor: Color {
        if power > 0.1 {
            return .green
        } else if power < -0.1 {
            return .orange
        } else {
            return .gray
        }
    }

    var body: some View {
        ZStack {
            // 全黑背景
            Color.black.ignoresSafeArea()

            // 主体：超大功率数字
            GeometryReader { geo in
                let fontSize = min(geo.size.width * 0.45, geo.size.height * 0.7)
                let unitSize = fontSize * 0.25

                VStack(spacing: 0) {
                    Spacer()

                    // 状态标签
                    Text(powerLabel)
                        .font(.system(size: fontSize * 0.07, weight: .medium, design: .monospaced))
                        .foregroundStyle(powerColor.opacity(0.7))
                        .tracking(4)

                    // 超大功率值
                    HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.02) {
                        Text(powerText)
                            .font(.system(size: fontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(powerColor)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(powerUnit)
                            .font(.system(size: unitSize, weight: .medium, design: .rounded))
                            .foregroundStyle(powerColor.opacity(0.6))
                            .padding(.bottom, unitSize * 0.3)
                    }
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: powerText)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            // 右下角小字：电压 / 电流 + SoC 圆环
            VStack(alignment: .trailing, spacing: 4) {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    Spacer()
                    // 小 SoC 圆环
                    miniSocRing
                    VStack(alignment: .trailing, spacing: 3) {
                        miniMetric(value: String(format: "%.1fV", data.totalVoltage))
                        miniMetric(value: String(format: "%.2fA", data.current))
                    }
                }
            }
            .padding(20)
        }
        .statusBarHidden(true)
    }

    /// 小型 SoC 圆环，类似 Android 通知栏电池图标
    private var miniSocRing: some View {
        let size: CGFloat = 32
        let lineWidth: CGFloat = 3.5
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(data.soc / 100.0))
                .stroke(socRingColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.0f", data.soc))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: size, height: size)
    }

    private var socRingColor: Color {
        if data.soc > 60 { return .green }
        if data.soc > 20 { return .orange }
        return .red
    }

    private func miniMetric(value: String) -> some View {
        Text(value)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
    }
}

#Preview {
    PowerGaugeView(data: .preview)
        .previewInterfaceOrientation(.landscapeLeft)
}
