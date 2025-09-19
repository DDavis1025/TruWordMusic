//
//  MainAppView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

enum AppTab {
    case home
    case search
}

struct MainAppView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor
    @StateObject private var keyboardObserver = KeyboardObserver()

    @State private var selectedSongForDetail: Song? = nil
    @State private var selectedTab: AppTab = .home
    @State private var homeNavigationPath = NavigationPath()
    @State private var searchNavigationPath = NavigationPath()

    private let tabBarHeight: CGFloat = 49

    var hasBottomTabBar: Bool {
        !(UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - Main TabView
            TabView(selection: $selectedTab) {
                ContentView(playerManager: playerManager, networkMonitor: networkMonitor, navigationPath: $homeNavigationPath)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(AppTab.home)

                SearchView(playerManager: playerManager, networkMonitor: networkMonitor, keyboardObserver: keyboardObserver, navigationPath: $searchNavigationPath)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppTab.search)
            }

            // MARK: - Bottom Player
            if let song = playerManager.currentlyPlayingSong,
               !keyboardObserver.isKeyboardVisible {
                Button(action: { selectedSongForDetail = song }) {
                    BottomPlayerView(
                        song: song,
                        isPlaying: $playerManager.isPlaying,
                        togglePlayPause: playerManager.togglePlayPause,
                        playerIsReady: playerManager.playerIsReady
                    )
                    .id(song.id)
                }
                .buttonStyle(.plain)
                .padding(.bottom, hasBottomTabBar ? tabBarHeight : 0)
            }
        }
        // MARK: - Track Detail Full Screen Cover
        .fullScreenCover(item: $selectedSongForDetail) { _ in
            if let song = playerManager.currentlyPlayingSong {
                TrackDetailView(
                    song: Binding(
                        get: { playerManager.currentlyPlayingSong ?? song },
                        set: { playerManager.currentlyPlayingSong = $0 }
                    ),
                    isPlaying: $playerManager.isPlaying,
                    togglePlayPause: playerManager.togglePlayPause,
                    isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                    albumWithTracks: $playerManager.albumWithTracks,
                    songs: $playerManager.songs,
                    playerIsReady: $playerManager.playerIsReady,
                    networkMonitor: networkMonitor,
                    playerManager: playerManager,
                    appleMusicSubscription: $playerManager.appleMusicSubscription,
                    selectedAlbum: $playerManager.selectedAlbum,
                    activeTab: $selectedTab,
                    homeNavigationPath: $homeNavigationPath,
                    searchNavigationPath: $searchNavigationPath
                )
            }
        }

        .animation(.spring(), value: playerManager.currentlyPlayingSong)
        .animation(.spring(), value: keyboardObserver.isKeyboardVisible)
    }
}



extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

