//
//  BMSSimulator.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import Foundation
import UIKit

/// 模拟 BMS 数据源，用于开发调试
/// 生成随机但合理的电池数据，模拟真实 BMS 行为
final class BMSSimulator {
    private var timerSource: DispatchSourceTimer?
    private weak var dataStore: BMSDataStore?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// 模拟参数
    private var baseSoC: Double = 78.0
    private var baseCurrent: Double = -35.0 // 负值=放电
    private let cellCount = 16
    private var tickCount = 0

    init(dataStore: BMSDataStore) {
        self.dataStore = dataStore
    }

    /// 立即生成一次模拟数据
    func simulateOnce() {
        guard let dataStore = dataStore else { return }
        tickCount += 1

        // SoC 随机波动
        baseSoC += Double.random(in: -0.5...0.3)
        baseSoC = max(5, min(100, baseSoC))

        // 电流：大范围波动，偶尔出现大功率场景
        // 每 5-8 次随机触发一次大电流突变
        if tickCount % Int.random(in: 5...8) == 0 {
            // 大功率突发：±50~100A
            baseCurrent = Double.random(in: -100 ... -50) * (Bool.random() ? 1 : -1)
        } else {
            baseCurrent += Double.random(in: -5.0...5.0)
        }
        baseCurrent = max(-120, min(120, baseCurrent))

        // 基础 Cell 电压根据 SoC 推算 (~3.0V@0% ~ 3.65V@100%)
        let baseCellVoltage = 3.0 + (baseSoC / 100.0) * 0.65

        // 每个 Cell 加一点随机偏差 (±5mV)
        let cellVoltages = (0..<cellCount).map { _ in
            baseCellVoltage + Double.random(in: -0.005...0.005)
        }

        let totalVoltage = cellVoltages.reduce(0, +)

        let data = BMSData(
            current: baseCurrent,
            soc: baseSoC,
            totalVoltage: totalVoltage,
            cellVoltages: cellVoltages,
            temp1: Double.random(in: 22...28),
            temp2: Double.random(in: 21...27),
            mosfetTemp: Double.random(in: 30...38),
            remainCapacity: baseSoC / 100.0 * 81.0,
            fullChargeCapacity: 81.0,
            cycleCount: 42,
            totalCycleCapacity: 3402.0 + Double(tickCount) * 0.1,
            lastUpdated: Date()
        )

        dataStore.update(with: data)
        dataStore.connectionState = .connected
    }

    /// 开始定时模拟（每 2 秒更新一次）
    /// 使用 DispatchSourceTimer + beginBackgroundTask 以支持后台运行
    func startContinuous() {
        simulateOnce()
        requestBackgroundTime()

        let queue = DispatchQueue.global(qos: .utility)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 2, repeating: 2.0)
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.simulateOnce()
            }
        }
        source.resume()
        timerSource = source
    }

    /// 停止定时模拟
    func stop() {
        timerSource?.cancel()
        timerSource = nil
        endBackgroundTask()
        dataStore?.connectionState = .disconnected
    }

    var isRunning: Bool {
        timerSource != nil
    }

    // MARK: - Background Task

    /// 申请后台执行时间，到期后重新申请（延长 simulate 模式后台存活）
    private func requestBackgroundTime() {
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "BMSSimulator"
        ) { [weak self] in
            // 到期回调：做最后一次更新，然后重新申请
            self?.simulateOnce()
            self?.endBackgroundTask()
            // 尝试立即重新申请新的后台任务（系统可能拒绝）
            self?.requestBackgroundTime()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}
