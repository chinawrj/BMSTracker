//
//  LiveActivityManager.swift
//  BMSTracker
//
//  Created by Rujun Wang on 3/13/26.
//

import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "com.linetkux.BMSTracker", category: "LiveActivity")

/// 管理 BMS 实时活动（锁屏/灵动岛）
final class LiveActivityManager {
    private var activity: Activity<BMSActivityAttributes>?
    private var updateCount: Int = 0

    init() {
        // 清理上次 app 被杀后遗留的 Live Activity
        endAllStaleActivities()
    }

    /// 启动 Live Activity
    func startActivity(deviceName: String, data: BMSData) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities 未授权")
            return
        }

        // 结束所有已有活动（包括遗留的）
        endAllStaleActivities()

        updateCount = 0
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
        updateCount += 1
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

    /// 结束所有遗留的 BMSActivityAttributes 类型 Live Activity
    private func endAllStaleActivities() {
        // 结束当前持有的
        if let activity {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            self.activity = nil
        }
        // 结束系统中所有同类型的（含上次 app 被杀后遗留的）
        for existing in Activity<BMSActivityAttributes>.activities {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            logger.notice("🧹 清理遗留 Live Activity: \(existing.id)")
        }
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
            lastUpdated: data.lastUpdated,
            updateCount: updateCount
        )
    }
}
