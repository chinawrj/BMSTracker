//
//  WatchPayload.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import Foundation

/// iOS ↔ Watch 之间传输 BMS 数据的编解码工具
/// 将来 Watch target 也引用此文件，确保两端格式一致
enum WatchPayload {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// 将 BMSData 编码为 WCSession 可传输的 [String: Any] 字典
    static func encode(_ data: BMSData) -> [String: Any] {
        // applicationContext / userInfo 只接受 plist-compatible 类型
        // 用 JSON data 作为值，保证 Codable 兼容
        guard let jsonData = try? encoder.encode(data) else { return [:] }
        return [
            "bmsData": jsonData,
            "timestamp": data.lastUpdated.timeIntervalSince1970
        ]
    }

    /// 从 WCSession 收到的字典中解码 BMSData
    static func decode(from dict: [String: Any]) -> BMSData? {
        guard let jsonData = dict["bmsData"] as? Data else { return nil }
        return try? decoder.decode(BMSData.self, from: jsonData)
    }
}
