//
//  TruWord_MusicApp.swift
//  TruWord Music
//
//  Created by Dillon Davis on 1/31/25.
//

import SwiftUI

@main
struct TruWord_MusicApp: App {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.35)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    var body: some Scene {
        WindowGroup {
            MainAppView()
        }
    }
}
