//
//  BMSData.swift
//  BMSTracker
//
//  Created by Rujun Wang on 3/3/26.
//

import Foundation

/// BMS 数据模型，存储从 BLE 获取的电池管理系统信息
struct BMSData: Codable, Sendable {
    /// 电流 (A)，正值为充电，负值为放电
    var current: Double
    /// 电量百分比 (0–100)
    var soc: Double
    /// 总电压 (V)
    var totalVoltage: Double
    /// 各 Cell 电压 (V)，最多 32 个
    var cellVoltages: [Double]
    /// 温度传感器 1 (°C)
    var temp1: Double
    /// 温度传感器 2 (°C)
    var temp2: Double
    /// MOS 管温度 (°C)
    var mosfetTemp: Double
    /// 剩余容量 (Ah)
    var remainCapacity: Double
    /// 满充容量 (Ah)
    var fullChargeCapacity: Double
    /// 循环次数
    var cycleCount: Int
    /// 累计循环容量 (Ah)
    var totalCycleCapacity: Double
    /// 最后更新时间
    var lastUpdated: Date

    var cellCount: Int { cellVoltages.count }

    /// 最低 Cell 电压
    var minCellVoltage: Double? { cellVoltages.min() }
    /// 最高 Cell 电压
    var maxCellVoltage: Double? { cellVoltages.max() }
    /// Cell 电压差
    var cellVoltageDelta: Double? {
        guard let min = minCellVoltage, let max = maxCellVoltage else { return nil }
        return max - min
    }

    static let placeholder = BMSData(
        current: 0.0,
        soc: 0.0,
        totalVoltage: 0.0,
        cellVoltages: [],
        temp1: 0, temp2: 0, mosfetTemp: 0,
        remainCapacity: 0, fullChargeCapacity: 0,
        cycleCount: 0, totalCycleCapacity: 0,
        lastUpdated: .distantPast
    )

    static let preview = BMSData(
        current: -12.5,
        soc: 78.3,
        totalVoltage: 52.8,
        cellVoltages: [
            3.312, 3.308, 3.315, 3.310, 3.318, 3.305,
            3.311, 3.309, 3.314, 3.307, 3.316, 3.303,
            3.313, 3.306, 3.317, 3.302
        ],
        temp1: 25.3, temp2: 24.8, mosfetTemp: 32.1,
        remainCapacity: 68.5, fullChargeCapacity: 81.0,
        cycleCount: 42, totalCycleCapacity: 3402.0,
        lastUpdated: Date()
    )
}
