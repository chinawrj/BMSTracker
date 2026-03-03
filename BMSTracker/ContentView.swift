//
//  ContentView.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

struct ContentView: View {
    var dataStore: BMSDataStore
    var bleManager: BLEManager
    var simulator: BMSSimulator

    @State private var isSimulating = false

    private var data: BMSData { dataStore.bmsData }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 连接状态栏
                    connectionStatusBar

                    // SoC 环形图 + 概览
                    socOverviewCard

                    // 电流 / 总电压
                    HStack(spacing: 12) {
                        metricCard(
                            title: "电流",
                            value: String(format: "%.2f", data.current),
                            unit: "A",
                            icon: "bolt.fill",
                            color: data.current < 0 ? .orange : .green
                        )
                        metricCard(
                            title: "总电压",
                            value: String(format: "%.2f", data.totalVoltage),
                            unit: "V",
                            icon: "powerplug.fill",
                            color: .blue
                        )
                    }

                    // Cell 电压网格
                    CellVoltageGridView(
                        cellVoltages: data.cellVoltages,
                        minVoltage: data.minCellVoltage,
                        maxVoltage: data.maxCellVoltage
                    )

                    // 最后更新时间
                    if dataStore.hasData {
                        lastUpdateFooter
                    }
                }
                .padding()
            }
            .navigationTitle("BMS Monitor")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    simulateButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    bleConnectionButton
                }
            }
            .refreshable {
                // 下拉刷新：触发重新读取缓存
                dataStore.loadFromCache()
            }
        }
    }

    // MARK: - 连接状态栏

    private var connectionStatusBar: some View {
        HStack {
            Circle()
                .fill(connectionColor)
                .frame(width: 10, height: 10)
            Text(dataStore.connectionState.rawValue)
                .font(.subheadline)
            Spacer()
            if dataStore.hasData {
                Text("\(data.cellCount) Cells")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionColor: Color {
        switch dataStore.connectionState {
        case .connected: return .green
        case .scanning, .connecting: return .orange
        case .disconnected: return .red
        }
    }

    // MARK: - SoC 环形概览

    private var socOverviewCard: some View {
        HStack(spacing: 24) {
            // SoC 环形图
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(data.soc / 100.0))
                    .stroke(socColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: data.soc)
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", data.soc))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            // 右侧概要
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("SoC")
                        .font(.headline)
                } icon: {
                    Image(systemName: socIcon)
                        .foregroundStyle(socColor)
                }

                if let delta = data.cellVoltageDelta {
                    HStack(spacing: 4) {
                        Text("Cell 压差")
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f mV", delta * 1000))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }

                if let min = data.minCellVoltage, let max = data.maxCellVoltage {
                    HStack(spacing: 4) {
                        Text("范围")
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.3f – %.3f V", min, max))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var socColor: Color {
        if data.soc > 60 { return .green }
        if data.soc > 20 { return .orange }
        return .red
    }

    private var socIcon: String {
        if data.soc > 75 { return "battery.100" }
        if data.soc > 50 { return "battery.75" }
        if data.soc > 25 { return "battery.50" }
        return "battery.25"
    }

    // MARK: - 数值卡片

    private func metricCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 最后更新

    private var lastUpdateFooter: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
            Text("最后更新: \(data.lastUpdated, style: .relative)前")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    // MARK: - 模拟按钮

    private var simulateButton: some View {
        Button {
            if isSimulating {
                simulator.stop()
                isSimulating = false
            } else {
                simulator.startContinuous()
                isSimulating = true
            }
        } label: {
            Image(systemName: isSimulating ? "stop.circle.fill" : "play.circle.fill")
                .foregroundStyle(isSimulating ? .red : .green)
        }
    }

    // MARK: - BLE 连接按钮

    private var bleConnectionButton: some View {
        Button {
            switch dataStore.connectionState {
            case .disconnected:
                bleManager.startScanning()
            case .scanning, .connecting:
                bleManager.stopScanning()
            case .connected:
                bleManager.disconnect()
            }
        } label: {
            Image(systemName: bleButtonIcon)
        }
    }

    private var bleButtonIcon: String {
        switch dataStore.connectionState {
        case .disconnected: return "antenna.radiowaves.left.and.right"
        case .scanning, .connecting: return "antenna.radiowaves.left.and.right.slash"
        case .connected: return "link.circle.fill"
        }
    }
}

#Preview {
    @Previewable var store = BMSDataStore()
    @Previewable var bleManager: BLEManager? = nil

    let _ = {
        store.bmsData = .preview
        store.connectionState = .connected
    }()

    ContentView(
        dataStore: store,
        bleManager: bleManager ?? BLEManager(dataStore: store),
        simulator: BMSSimulator(dataStore: store)
    )
}
