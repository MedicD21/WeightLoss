//
//  LoggedApp.swift
//  Logged
//
//  Created by Dustin Schaaf on 1/26/26.
//

import SwiftUI

@main
struct LoggedApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if canImport(WatchConnectivity)
                    WatchConnectivityService.shared.activate()
                    #endif
                }
        }
    }
}
