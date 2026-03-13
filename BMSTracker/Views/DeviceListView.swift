//
//  DeviceListView.swift
//  BMSTracker
//
//  Created by Rujun Wang on 3/6/26.
//

import SwiftUI

/// BLE 设备选择弹窗
/// 显示扫描到的 JK-BMS 设备列表，点击后连接
struct DeviceListView: View {
    var bleManager: BLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bleManager.discoveredDevices.isEmpty {
                    scanningPlaceholder
                } else {
                    deviceList
                }
            }
            .navigationTitle("选择 BMS 设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        bleManager.stopScanning()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if bleManager.isScanning {
                        ProgressView()
                    } else {
                        Button {
                            bleManager.startScanning()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 扫描中占位

    private var scanningPlaceholder: some View {
        ContentUnavailableView {
            Label("搜索 BMS 设备中…", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            VStack(spacing: 4) {
                Text("请确保 JK-BMS 设备已开机且在蓝牙范围内")
                scanStats
            }
        }
    }

    // MARK: - 扫描统计

    private var scanStats: some View {
        Text("已扫描 BLE 设备: \(bleManager.totalDiscoveredCount)  |  JK-BMS: \(bleManager.discoveredDevices.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    // MARK: - 设备列表

    private var deviceList: some View {
        List {
            Section {
                ForEach(bleManager.discoveredDevices) { device in
                    Button {
                        bleManager.connect(to: device)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 4) {
                                    Text(device.id.uuidString.prefix(8) + "…")
                                    if device.matchReason == "FFE0" {
                                        Text("(FFE0)")
                                            .foregroundStyle(.orange)
                                    } else if device.matchReason == "both" {
                                        Text("(名称+FFE0)")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // 信号强度指示
                            rssiIndicator(device.rssi)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section {
                scanStats
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - RSSI 信号图标

    private func rssiIndicator(_ rssi: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: rssiIcon(rssi))
                .foregroundStyle(rssiColor(rssi))
            Text("\(rssi) dBm")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func rssiIcon(_ rssi: Int) -> String {
        if rssi >= -50 { return "wifi" }
        if rssi >= -70 { return "wifi" }
        if rssi >= -85 { return "wifi.exclamationmark" }
        return "wifi.slash"
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -50 { return .green }
        if rssi >= -70 { return .yellow }
        if rssi >= -85 { return .orange }
        return .red
    }
}
