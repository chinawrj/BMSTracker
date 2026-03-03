//
//  BMSTrackerWatchKitApp.swift
//  BMSTrackerWatchKit Watch App
//
//  Created by 王如军 on 3/3/26.
//

import SwiftUI

@main
struct BMSTrackerWatchKit_Watch_AppApp: App {
    @State private var receiver = WatchDataReceiver()

    var body: some Scene {
        WindowGroup {
            ContentView(receiver: receiver)
                .onAppear {
                    receiver.loadCachedData()
                }
        }
    }
}
