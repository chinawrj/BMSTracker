//
//  WatchDataReceiver.swift
//  BMSTrackerWatchKit Watch App
//
//  Created by 王如军 on 3/3/26.
//

import Foundation
import WatchConnectivity
import Observation

/// Watch 端 WCSession 数据接收器
/// 接收 iOS 端通过 WatchConnectivity 推送的 BMS 数据
@Observable
final class WatchDataReceiver: NSObject {
    /// 当前 BMS 数据
    var bmsData: BMSData = .placeholder

    /// 累计数据更新次数（从iOS端同步）
    var updateCount: Int = 0

    /// 是否已收到过数据
    var hasData: Bool {
        bmsData.lastUpdated != Date.distantPast
    }

    /// iOS App 是否可达
    var isCompanionReachable: Bool = false

    private var session: WCSession?

    override init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// 从本地缓存加载上次数据
    func loadCachedData() {
        guard let data = UserDefaults.standard.data(forKey: "WatchBMSCache"),
              let cached = try? JSONDecoder().decode(BMSData.self, from: data) else {
            return
        }
        self.bmsData = cached
    }

    /// 保存到本地缓存
    private func cacheData(_ data: BMSData) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: "WatchBMSCache")
    }

    /// 处理收到的数据
    private func handleReceivedPayload(_ payload: [String: Any]) {
        guard let data = WatchPayload.decode(from: payload) else { return }
        self.bmsData = data
        self.updateCount = WatchPayload.decodeUpdateCount(from: payload)
        cacheData(data)
    }
}

// MARK: - WCSessionDelegate

extension WatchDataReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith activationState: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor in
            self.isCompanionReachable = session.isReachable

            // 激活时检查是否有 applicationContext 待处理
            if !session.receivedApplicationContext.isEmpty {
                handleReceivedPayload(session.receivedApplicationContext)
            }
        }
    }

    /// 收到 applicationContext 更新
    nonisolated func session(_ session: WCSession,
                              didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            handleReceivedPayload(applicationContext)
        }
    }

    /// 收到即时消息（iOS 端 sendMessage）
    nonisolated func session(_ session: WCSession,
                              didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleReceivedPayload(message)
        }
    }

    /// 收到 userInfo 传输
    nonisolated func session(_ session: WCSession,
                              didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handleReceivedPayload(userInfo)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isCompanionReachable = session.isReachable
        }
    }
}
