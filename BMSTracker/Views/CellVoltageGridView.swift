//
//  CellVoltageGridView.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

/// 单个 Cell 电压卡片
struct CellVoltageCard: View {
    let index: Int
    let voltage: Double
    let minVoltage: Double?
    let maxVoltage: Double?

    private var voltageColor: Color {
        guard let min = minVoltage, let max = maxVoltage, max > min else {
            return .primary
        }
        let range = max - min
        let position = (voltage - min) / range

        if range < 0.010 {
            // 压差 < 10mV，全部显示绿色
            return .green
        } else if position < 0.2 {
            return .red
        } else if position < 0.4 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(index + 1)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
            Text(String(format: " %.3f", voltage))
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(voltageColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Cell 电压网格视图
struct CellVoltageGridView: View {
    let cellVoltages: [Double]
    let minVoltage: Double?
    let maxVoltage: Double?

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏
            HStack {
                Label("Cell 电压 (V)", systemImage: "battery.100")
                    .font(.headline)
                Spacer()
                if let min = minVoltage, let max = maxVoltage {
                    Text("Δ \(String(format: "%.1f", (max - min) * 1000)) mV")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            if cellVoltages.isEmpty {
                Text("暂无 Cell 数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(cellVoltages.enumerated()), id: \.offset) { index, voltage in
                        CellVoltageCard(
                            index: index,
                            voltage: voltage,
                            minVoltage: minVoltage,
                            maxVoltage: maxVoltage
                        )
                    }
                }
            }

            // 图例
            if !cellVoltages.isEmpty {
                HStack(spacing: 16) {
                    legendItem(color: .green, label: "正常")
                    legendItem(color: .orange, label: "偏低")
                    legendItem(color: .red, label: "最低")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

#Preview {
    CellVoltageGridView(
        cellVoltages: BMSData.preview.cellVoltages,
        minVoltage: BMSData.preview.minCellVoltage,
        maxVoltage: BMSData.preview.maxCellVoltage
    )
    .padding()
}
