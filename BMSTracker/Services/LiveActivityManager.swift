//
//  LiveActivityManager.swift
//  BMSTracker
//
//  Created by 王如军 on 3/13/26.
//

import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "com.linetkux.BMSTracker", category: "LiveActivity")

/// 管理 BMS 实时活动（锁屏/灵动岛）
final class LiveActivityManager {
    private var activity: Activity<BMSActivityAttributes>?

    /// 启动 Live Activity
    func startActivity(deviceName: String, data: BMSData) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities 未授权")
            return
        }

        // 如果已有活动，先结束
        if activity != nil {
            endActivity()
        }

        let attributes = BMSActivityAttributes(deviceName: deviceName)
        let state = contentState(from: data)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(300)),
                pushType: nil
            )
            logger.notice("✅ Live Activity 已启动")
        } catch {
            logger.error("❌ Live Activity 启动失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 更新 Live Activity 数据
    func updateActivity(with data: BMSData) {
        guard let activity else { return }
        let state = contentState(from: data)
        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(300)))
        }
    }

    /// 结束 Live Activity
    func endActivity() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        logger.notice("⏹ Live Activity 已结束")
    }

    /// 当前是否有活动运行中
    var isActive: Bool {
        activity != nil
    }

    // MARK: - Private

    private func contentState(from data: BMSData) -> BMSActivityAttributes.ContentState {
        .init(
            soc: data.soc,
            totalVoltage: data.totalVoltage,
            current: data.current,
            temp1: data.temp1,
            remainCapacity: data.remainCapacity,
            fullChargeCapacity: data.fullChargeCapacity,
            lastUpdated: data.lastUpdated
        )
    }
}
