//
//  BMSTrackerApp.swift
//  BMSTracker
//
//  Created by Rujun Wang on 3/3/26.
//

import SwiftUI

@main
struct BMSTrackerApp: App {
    @State private var dataStore = BMSDataStore()
    @State private var watchSession = WatchSessionManager()
    @State private var liveActivityManager = LiveActivityManager()
    @State private var bleManager: BLEManager?
    @State private var simulator: BMSSimulator?

    var body: some Scene {
        WindowGroup {
            if let bleManager, let simulator {
                ContentView(
                    dataStore: dataStore,
                    bleManager: bleManager,
                    simulator: simulator,
                    liveActivityManager: liveActivityManager
                )
            } else {
                ProgressView("初始化中...")
                    .task {
                        dataStore.watchSession = watchSession
                        dataStore.liveActivityManager = liveActivityManager
                        dataStore.loadFromCache()
                        bleManager = BLEManager(dataStore: dataStore)
                        simulator = BMSSimulator(dataStore: dataStore)
                    }
            }
        }
    }
}
