//
//  BMSActivityAttributes.swift
//  BMSTrackerWidgets
//
//  Created by 王如军 on 3/13/26.
//

import ActivityKit
import Foundation

/// Live Activity 数据模型（Widget Extension 拷贝）
struct BMSActivityAttributes: ActivityAttributes {
    /// 设备名称（活动启动时设置，不可变）
    var deviceName: String

    struct ContentState: Codable, Hashable {
        var soc: Double
        var totalVoltage: Double
        var current: Double
        var temp1: Double
        var remainCapacity: Double
        var fullChargeCapacity: Double
        var lastUpdated: Date

        /// 实时功率 (W)
        var power: Double {
            totalVoltage * current
        }
    }
}
