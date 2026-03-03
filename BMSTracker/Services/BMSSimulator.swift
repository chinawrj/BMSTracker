//
//  BMSSimulator.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import Foundation

/// 模拟 BMS 数据源，用于开发调试
/// 生成随机但合理的电池数据，模拟真实 BMS 行为
final class BMSSimulator {
    private var timer: Timer?
    private weak var dataStore: BMSDataStore?

    /// 模拟参数
    private var baseSoC: Double = 78.0
    private var baseCurrent: Double = -12.5 // 负值=放电
    private let cellCount = 16

    init(dataStore: BMSDataStore) {
        self.dataStore = dataStore
    }

    /// 立即生成一次模拟数据
    func simulateOnce() {
        guard let dataStore = dataStore else { return }

        // SoC 随机波动
        baseSoC += Double.random(in: -0.5...0.3)
        baseSoC = max(5, min(100, baseSoC))

        // 电流随机波动
        baseCurrent += Double.random(in: -1.0...1.0)
        baseCurrent = max(-30, min(30, baseCurrent))

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
            lastUpdated: Date()
        )

        dataStore.update(with: data)
        dataStore.connectionState = .connected
    }

    /// 开始定时模拟（每 2 秒更新一次）
    func startContinuous() {
        simulateOnce()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.simulateOnce()
        }
    }

    /// 停止定时模拟
    func stop() {
        timer?.invalidate()
        timer = nil
        dataStore?.connectionState = .disconnected
    }

    var isRunning: Bool {
        timer != nil
    }
}
