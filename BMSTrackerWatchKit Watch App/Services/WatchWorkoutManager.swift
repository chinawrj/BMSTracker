//
//  WatchWorkoutManager.swift
//  BMSTrackerWatchKit Watch App
//
//  Created by Rujun Wang on 3/13/26.
//

import Foundation
import HealthKit
import os

private let logger = Logger(subsystem: "com.linetkux.BMSTracker.watchkitapp", category: "Workout")

/// 利用 HKWorkoutSession 保持 Watch app 前台活跃（类似运动 app）
/// 启动后屏幕保持常亮，降腕后进入 Always-On Display 模式
@MainActor
final class WatchWorkoutManager: NSObject, Observable {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    var isActive: Bool {
        workoutSession != nil
    }

    /// 请求 HealthKit 权限并启动 workout session
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.warning("HealthKit 不可用")
            return
        }

        // 请求最小权限（只需要 workout 类型）
        let workoutType = HKQuantityType.workoutType()
        let typesToShare: Set<HKSampleType> = [workoutType]
        let typesToRead: Set<HKObjectType> = [workoutType]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            if let error {
                logger.error("HealthKit 授权失败: \(error.localizedDescription, privacy: .public)")
                return
            }
            if success {
                Task { @MainActor in
                    self?.startWorkoutSession()
                }
            }
        }
    }

    /// 停止 workout session
    func stop() {
        guard let session = workoutSession else { return }
        session.end()
        workoutBuilder?.endCollection(withEnd: Date()) { _, _ in }
        workoutBuilder?.finishWorkout { _, _ in }
        workoutSession = nil
        workoutBuilder = nil
        logger.notice("⏹ Workout session 已停止")
    }

    // MARK: - Private

    private func startWorkoutSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, error in
                if let error {
                    logger.error("Workout collection 启动失败: \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.notice("✅ Workout session 已启动（Always-On Display 激活）")
                }
            }
        } catch {
            logger.error("❌ Workout session 创建失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        logger.notice("Workout state: \(fromState.rawValue) → \(toState.rawValue)")
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        logger.error("Workout session 失败: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}
