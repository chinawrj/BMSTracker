//
//  BMSDataStore.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import Foundation
import Observation

/// BMS 数据缓存层
/// BLE 后台任务写入数据，UI 层读取并自动刷新
@Observable
final class BMSDataStore {
    /// 当前 BMS 数据
    var bmsData: BMSData = .placeholder

    /// BLE 连接状态
    var connectionState: ConnectionState = .disconnected

    /// 是否有有效数据
    var hasData: Bool {
        bmsData.lastUpdated != Date.distantPast
    }

    /// 上次更新距今的秒数
    var secondsSinceLastUpdate: Int {
        Int(Date().timeIntervalSince(bmsData.lastUpdated))
    }

    enum ConnectionState: String {
        case disconnected = "未连接"
        case scanning = "搜索中"
        case connecting = "连接中"
        case connected = "已连接"

        var color: String {
            switch self {
            case .disconnected: return "red"
            case .scanning, .connecting: return "orange"
            case .connected: return "green"
            }
        }
    }

    // MARK: - Watch Connectivity

    /// Watch 会话管理器，数据更新时自动推送给 Apple Watch
    var watchSession: WatchSessionManager?

    /// Live Activity 管理器
    var liveActivityManager: LiveActivityManager?

    /// 累计数据更新次数
    var updateCount: Int = 0

    // MARK: - Cache Persistence

    private static let cacheKey = "BMSDataCache"

    /// 从 UserDefaults 加载缓存
    func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode(BMSData.self, from: data) else {
            return
        }
        self.bmsData = cached
    }

    /// 保存到 UserDefaults 缓存
    func saveToCache() {
        guard let data = try? JSONEncoder().encode(bmsData) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    /// 由 BLE 后台任务调用，更新数据并持久化，同时推送给 Watch 和 Live Activity
    func update(with newData: BMSData) {
        updateCount += 1
        self.bmsData = newData
        saveToCache()
        pushToWatch(newData)
        liveActivityManager?.updateActivity(with: newData)
    }

    /// 推送数据给 Apple Watch
    private func pushToWatch(_ data: BMSData) {
        guard let watchSession = watchSession else { return }
        if watchSession.isReachable {
            // Watch 当前活跃，用即时消息（低延迟）
            watchSession.sendBMSDataInteractively(data, updateCount: updateCount)
        } else {
            // Watch 不活跃，用 applicationContext（下次唤醒时递送）
            watchSession.sendBMSData(data, updateCount: updateCount)
        }
    }
}
