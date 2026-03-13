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
            // 顶部：设备名称 + 更新次数
            HStack {
                Label(context.attributes.deviceName, systemImage: "battery.100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(context.state.updateCount)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // SOC + 功率 突出行
            HStack(spacing: 0) {
                // SOC
                VStack(spacing: 4) {
                    Text(String(format: "%.0f%%", context.state.soc))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(socColor(context.state.soc))
                    ProgressView(value: context.state.soc / 100)
                        .tint(socColor(context.state.soc))
                }
                .frame(maxWidth: .infinity)

                // 功率（指示条用电流/2C）
                VStack(spacing: 4) {
                    Text(String(format: "%.0fW", context.state.power))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(context.state.current < 0 ? .orange : .green)
                    let cRate = context.state.fullChargeCapacity > 0
                        ? min(abs(context.state.current) / (context.state.fullChargeCapacity * 2), 1.0)
                        : 0
                    ProgressView(value: cRate)
                        .tint(cRateColor(cRate))
                }
                .frame(maxWidth: .infinity)
            }

            // 数据网格：电压 / 电流 / 温度
            HStack(spacing: 0) {
                statItem(label: "电压",
                         value: String(format: "%.1fV", context.state.totalVoltage),
                         color: .blue)
                statItem(label: "电流",
                         value: String(format: "%.2fA", context.state.current),
                         color: context.state.current < 0 ? .orange : .green)
                statItem(label: "温度",
                         value: String(format: "%.1f°C", context.state.temp1),
                         color: context.state.temp1 > 45 ? .red : .primary)
            }

            // 底部：容量 + 更新时间
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

    @ViewBuilder
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
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

    /// 电流/2C 比率颜色：<0.5C 绿色，0.5-1C 橙色，>1C 红色
    private func cRateColor(_ ratio: Double) -> Color {
        if ratio > 0.5 { return .red }      // >1C
        if ratio > 0.25 { return .orange }   // >0.5C
        return .green
    }
}
