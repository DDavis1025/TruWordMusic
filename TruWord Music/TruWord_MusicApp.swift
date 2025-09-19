//
//  TruWord_MusicApp.swift
//  TruWord Music
//
//  Created by Dillon Davis on 1/31/25.
//

import SwiftUI

//
//  TruWord_MusicApp.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

@main
struct TruWord_MusicApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var playerManager: PlayerManager

    init() {
        // Tab bar styling
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.35)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // Initialize PlayerManager once, using the same NetworkMonitor
        let manager = PlayerManager(networkMonitor: NetworkMonitor())
        _playerManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            MainAppView(playerManager: playerManager, networkMonitor: networkMonitor)
                .environmentObject(playerManager)
                .environmentObject(networkMonitor)
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
