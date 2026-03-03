//
//  BMSTrackerApp.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

@main
struct BMSTrackerApp: App {
    @State private var dataStore = BMSDataStore()
    @State private var bleManager: BLEManager?
    @State private var watchSession = WatchSessionManager()
    @State private var simulator: BMSSimulator?

    var body: some Scene {
        WindowGroup {
            ContentView(
                dataStore: dataStore,
                bleManager: bleManager ?? createBLEManager(),
                simulator: simulator ?? createSimulator()
            )
            .onAppear {
                dataStore.watchSession = watchSession
                dataStore.loadFromCache()
                if bleManager == nil {
                    bleManager = BLEManager(dataStore: dataStore)
                }
                if simulator == nil {
                    simulator = BMSSimulator(dataStore: dataStore)
                }
            }
        }
    }

    private func createBLEManager() -> BLEManager {
        BLEManager(dataStore: dataStore)
    }

    private func createSimulator() -> BMSSimulator {
        BMSSimulator(dataStore: dataStore)
    }
}
