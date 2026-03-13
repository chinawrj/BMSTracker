//
//  BMSLiveActivityView.swift
//  BMSTrackerWidgets
//
//  Created by 王如军 on 3/13/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BMSLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BMSActivityAttributes.self) { context in
            // 锁屏 / 通知横幅 UI
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // 灵动岛展开区域
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("电压")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1fV", context.state.totalVoltage))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("电流")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1fA", context.state.current))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(context.state.current < 0 ? .orange : .green)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f%%", context.state.soc))
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                        ProgressView(value: context.state.soc / 100)
                            .tint(socColor(context.state.soc))
                        Text(String(format: "%.0fW", context.state.power))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(String(format: "%.1f°C", context.state.temp1),
                              systemImage: "thermometer.medium")
                        Spacer()
                        Text(String(format: "%.1f / %.1f Ah",
                                    context.state.remainCapacity,
                                    context.state.fullChargeCapacity))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                // 灵动岛紧凑 - 左侧
                Label {
                    Text(String(format: "%.0f%%", context.state.soc))
                } icon: {
                    Image(systemName: socIcon(context.state.soc))
                }
                .font(.caption)
                .foregroundStyle(socColor(context.state.soc))
            } compactTrailing: {
                // 灵动岛紧凑 - 右侧
                Text(String(format: "%.0fW", context.state.power))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(context.state.current < 0 ? .orange : .green)
            } minimal: {
                // 灵动岛最小
                Image(systemName: socIcon(context.state.soc))
                    .foregroundStyle(socColor(context.state.soc))
            }
        }
    }

    // MARK: - 锁屏视图

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<BMSActivityAttributes>) -> some View {
        VStack(spacing: 8) {
            // 顶部：设备名称 + 功率
            HStack {
                Label(context.attributes.deviceName, systemImage: "battery.100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0fW", context.state.power))
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(context.state.current < 0 ? .orange : .green)
            }

            // SOC 进度条
            HStack(spacing: 12) {
                Text(String(format: "%.0f%%", context.state.soc))
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(socColor(context.state.soc))

                VStack(spacing: 4) {
                    ProgressView(value: context.state.soc / 100)
                        .tint(socColor(context.state.soc))

                    HStack {
                        Text(String(format: "%.1fV", context.state.totalVoltage))
                        Spacer()
                        Text(String(format: "%.2fA", context.state.current))
                        Spacer()
                        Text(String(format: "%.1f°C", context.state.temp1))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            // 底部：容量
            HStack {
                Text(String(format: "剩余 %.1f / %.1f Ah",
                            context.state.remainCapacity,
                            context.state.fullChargeCapacity))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(context.state.lastUpdated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    // MARK: - 辅助

    private func socColor(_ soc: Double) -> Color {
        if soc > 60 { return .green }
        if soc > 20 { return .orange }
        return .red
    }

    private func socIcon(_ soc: Double) -> String {
        if soc > 75 { return "battery.100" }
        if soc > 50 { return "battery.75" }
        if soc > 25 { return "battery.50" }
        return "battery.25"
    }
}
