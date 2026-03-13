//
//  WatchSessionManager.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import Foundation
import WatchConnectivity
import Observation

/// iOS 端 WatchConnectivity 管理器
/// 负责将 BMS 数据推送给配对的 Apple Watch
@Observable
final class WatchSessionManager: NSObject {
    /// Watch 是否可达
    var isReachable: Bool = false
    /// Watch App 是否已安装
    var isWatchAppInstalled: Bool = false
    /// 最后一次成功发送的时间
    var lastSentDate: Date?

    private var session: WCSession?

    override init() {
        super.init()
        activateIfSupported()
    }

    /// 激活 WCSession（仅在支持的设备上）
    private func activateIfSupported() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// 通过 applicationContext 发送最新 BMS 数据
    /// applicationContext 会在 Watch 端醒来时自动递送最新一条
    func sendBMSData(_ data: BMSData, updateCount: Int = 0) {
        guard let session = session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else {
            return
        }

        let payload = WatchPayload.encode(data, updateCount: updateCount)
        do {
            try session.updateApplicationContext(payload)
            lastSentDate = Date()
        } catch {
            // applicationContext 失败时，尝试 transferUserInfo 作为备选
            // transferUserInfo 保证递送，但会排队
            session.transferUserInfo(payload)
            lastSentDate = Date()
        }
    }

    /// 如果 Watch 当前可达，发送即时消息（低延迟）
    func sendBMSDataInteractively(_ data: BMSData, updateCount: Int = 0) {
        guard let session = session,
              session.isReachable else {
            // Watch 不可达，退回到 applicationContext
            sendBMSData(data, updateCount: updateCount)
            return
        }

        let payload = WatchPayload.encode(data, updateCount: updateCount)
        session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
            // 即时消息失败，退回到 applicationContext
            self?.sendBMSData(data, updateCount: updateCount)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith activationState: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        // Required for iOS delegate
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 重新激活以支持 Watch 切换
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
}
