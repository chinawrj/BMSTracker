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

    /// 功率显示文本（根据大小自动选择 W 或 kW）
    private var powerText: String {
        if absPower >= 1000 {
            return String(format: "%.2f", absPower / 1000)
        } else {
            return String(format: "%.0f", absPower)
        }
    }

    private var powerUnit: String {
        absPower >= 1000 ? "kW" : "W"
    }

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

            // 右下角小字：电压 / 电流 / SoC
            VStack(alignment: .trailing, spacing: 4) {
                Spacer()
                HStack(spacing: 0) {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        miniMetric(value: String(format: "%.1fV", data.totalVoltage))
                        miniMetric(value: String(format: "%.2fA", data.current))
                        miniMetric(value: String(format: "%.0f%%", data.soc))
                    }
                }
            }
            .padding(20)
        }
        .statusBarHidden(true)
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
