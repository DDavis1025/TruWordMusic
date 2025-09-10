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
    @Environment(\.scenePhase) private var scenePhase  // <-- add this
    
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var playerManager = PlayerManager()
    @StateObject private var keyboardObserver = KeyboardObserver()
    
    @State private var selectedSongForDetail: Song? = nil
    
    @State private var selectedTab:AppTab = .home
    @State private var homeNavigationPath = NavigationPath()
    @State private var searchNavigationPath = NavigationPath()
    
    private let tabBarHeight: CGFloat = 49
    
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
                .padding(.bottom, tabBarHeight)
            }
        }
        // MARK: - Track Detail Full Screen Cover
        
        .fullScreenCover(item: $selectedSongForDetail) { _ in
            if let _ = playerManager.currentlyPlayingSong {
                TrackDetailView(
                    song: Binding(
                        get: { playerManager.currentlyPlayingSong! },
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
        // MARK: - Scene Phase Listener
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                playerManager.onAppForeground()
            }
        }
    }
    
    // MARK: - Function to call when the app enters the foreground
        private func onAppForeground() {
            Task {
                playerManager.onAppForeground()
            }
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

