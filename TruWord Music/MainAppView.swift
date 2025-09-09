//
//  MainAppView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

struct MainAppView: View {
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var playerManager = PlayerManager()
    @StateObject private var keyboardObserver = KeyboardObserver()
    
    @State private var selectedSongForDetail: Song? = nil
    @State private var navigationPath = NavigationPath()
    
    private let tabBarHeight: CGFloat = 49
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - Main TabView
            TabView {
                ContentView(playerManager: playerManager, networkMonitor: networkMonitor, navigationPath: $navigationPath)
                    .tabItem { Label("Home", systemImage: "house.fill") }

                SearchView(playerManager: playerManager, networkMonitor: networkMonitor, keyboardObserver: keyboardObserver, navigationPath: $navigationPath)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
            .background(Color(.systemGray6).opacity(0.97).ignoresSafeArea(edges: .bottom))
            
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
        .fullScreenCover(item: $selectedSongForDetail) { song in
            TrackDetailView(
                song: song,
                isPlaying: $playerManager.isPlaying,
                togglePlayPause: playerManager.togglePlayPause,
                isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                albumWithTracks: $playerManager.albumWithTracks,
                playSong: { s in playerManager.playSong(s, from: []) },
                songs: .constant([]),
                playerIsReady: $playerManager.playerIsReady,
                networkMonitor: networkMonitor,
                appleMusicSubscription: $playerManager.appleMusicSubscription,
                navigationPath: $navigationPath,
                selectedAlbum: $playerManager.selectedAlbum
            )
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

