//
//  BMSData.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
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
    /// 各 Cell 电压 (V)，最多 24 个
    var cellVoltages: [Double]
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
        lastUpdated: Date()
    )
}
