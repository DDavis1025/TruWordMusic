//
//  TruWord_MusicApp.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit
import FirebaseCore
import FirebaseAnalytics

@main
struct TruWord_MusicApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var playerManager: PlayerManager
    @StateObject private var favoritesManager = FavoritesManager()

    init() {
        // ✅ Initialize Firebase FIRST
        FirebaseApp.configure()
        
        #if DEBUG
        Analytics.setAnalyticsCollectionEnabled(false)
        #endif
        
        // Initialize PlayerManager once, using the same NetworkMonitor
        let manager = PlayerManager(networkMonitor: NetworkMonitor())
        _playerManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            MainAppView(playerManager: playerManager, networkMonitor: networkMonitor)
                .environmentObject(playerManager)
                .environmentObject(networkMonitor)
                .environmentObject(favoritesManager)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        playerManager.onAppBackground()
                    case .active:
                        playerManager.onAppForeground()
                    default:
                        break
                    }
                }
        }
    }
}
