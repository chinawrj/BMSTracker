//
//  ContentView.swift
//  BMSTrackerWatchKit Watch App
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

struct ContentView: View {
    var receiver: WatchDataReceiver

    @State private var showPowerGauge = false
    @State private var workoutManager = WatchWorkoutManager()

    private var data: BMSData { receiver.bmsData }

    var body: some View {
        Group {
            if showPowerGauge {
                WatchPowerGaugeView(data: data, updateCount: receiver.updateCount, workoutManager: workoutManager)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        showPowerGauge = false
                    }
            } else {
                dashboardView
            }
        }
    }

    // MARK: - Dashboard

    private var dashboardView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // SoC 环形
                    socRing

                    // 电压 & 电流
                    HStack(spacing: 8) {
                        metricBlock(
                            label: "电压",
                            value: String(format: "%.1f", data.totalVoltage),
                            unit: "V",
                            color: .blue
                        )
                        metricBlock(
                            label: "电流",
                            value: String(format: "%.1f", data.current),
                            unit: "A",
                            color: data.current < 0 ? .orange : .green
                        )
                    }

                    // 温度
                    HStack(spacing: 8) {
                        metricBlock(
                            label: "T1",
                            value: String(format: "%.1f", data.temp1),
                            unit: "°C",
                            color: data.temp1 > 45 ? .red : .green
                        )
                        metricBlock(
                            label: "T2",
                            value: String(format: "%.1f", data.temp2),
                            unit: "°C",
                            color: data.temp2 > 45 ? .red : .green
                        )
                        metricBlock(
                            label: "MOS",
                            value: String(format: "%.1f", data.mosfetTemp),
                            unit: "°C",
                            color: data.mosfetTemp > 60 ? .red : .green
                        )
                    }

                    // 容量
                    HStack(spacing: 8) {
                        metricBlock(
                            label: "剩余",
                            value: String(format: "%.1f", data.remainCapacity),
                            unit: "Ah",
                            color: .cyan
                        )
                        metricBlock(
                            label: "满充",
                            value: String(format: "%.1f", data.fullChargeCapacity),
                            unit: "Ah",
                            color: .blue
                        )
                    }

                    // 循环
                    HStack(spacing: 8) {
                        metricBlock(
                            label: "循环",
                            value: "\(data.cycleCount)",
                            unit: "次",
                            color: .purple
                        )
                        metricBlock(
                            label: "累计",
                            value: String(format: "%.0f", data.totalCycleCapacity),
                            unit: "Ah",
                            color: .indigo
                        )
                    }

                    // Cell 压差
                    if let delta = data.cellVoltageDelta {
                        HStack {
                            Text("Cell 压差")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f mV", delta * 1000))
                                .fontWeight(.medium)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 4)
                    }

                    // Cell 电压列表（紧凑）
                    if !data.cellVoltages.isEmpty {
                        cellVoltageList
                    }

                    // 连接状态
                    connectionStatus
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("BMS")
            .onLongPressGesture(minimumDuration: 0.5) {
                showPowerGauge = true
            }
        }
    }

    // MARK: - SoC 环形图

    private var socRing: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(data.soc / 100.0))
                .stroke(socColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: data.soc)
            VStack(spacing: 0) {
                Text(String(format: "%.0f", data.soc))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
    }

    private var socColor: Color {
        if data.soc > 60 { return .green }
        if data.soc > 20 { return .orange }
        return .red
    }

    // MARK: - 数值块

    private func metricBlock(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cell 电压列表

    private var cellVoltageList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cell 电压 (V)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4),
            ], spacing: 3) {
                ForEach(Array(data.cellVoltages.enumerated()), id: \.offset) { index, voltage in
                    Text("\(index + 1) " + String(format: "%.3f", voltage))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(cellColor(voltage))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func cellColor(_ voltage: Double) -> Color {
        guard let min = data.minCellVoltage, let max = data.maxCellVoltage, max > min else {
            return .primary
        }
        let range = max - min
        if range < 0.010 { return .green }
        let position = (voltage - min) / range
        if position < 0.2 { return .red }
        if position < 0.4 { return .orange }
        return .green
    }

    // MARK: - 连接状态

    private var connectionStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(receiver.isCompanionReachable ? .green : .orange)
                .frame(width: 6, height: 6)
            Text(receiver.isCompanionReachable ? "iPhone 已连接" : "等待数据...")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Label("\(receiver.updateCount)", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}

#Preview {
    let receiver = WatchDataReceiver()
    receiver.bmsData = .preview
    return ContentView(receiver: receiver)
}
