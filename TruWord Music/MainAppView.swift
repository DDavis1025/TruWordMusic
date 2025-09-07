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

    @State private var selectedSongForDetail: Song? = nil
    private let tabBarHeight: CGFloat = 49

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - Tabs
            TabView {
                ContentView(playerManager: playerManager, networkMonitor: networkMonitor)
                    .tabItem { Label("Home", systemImage: "house.fill") }

                SearchView(playerManager: playerManager, networkMonitor: networkMonitor)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }

            // MARK: - Bottom Player Overlay
            if let song = playerManager.currentlyPlayingSong {
                Button(action: {
                    selectedSongForDetail = song
                }) {
                    BottomPlayerView(
                        song: song,
                        isPlaying: $playerManager.isPlaying,
                        togglePlayPause: playerManager.togglePlayPause,
                        playerIsReady: playerManager.playerIsReady
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, tabBarHeight) // Push above TabBar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // MARK: - Full Screen Track Detail
        .fullScreenCover(item: $selectedSongForDetail) { song in
            TrackDetailView(
                song: song,
                isPlaying: $playerManager.isPlaying,
                togglePlayPause: playerManager.togglePlayPause,
                bottomMessage: $playerManager.bottomMessage,
                isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                albumWithTracks: $playerManager.albumWithTracks,
                albums: [], // your albums array
                playSong: { s in playerManager.playSong(s, from: []) },
                songs: .constant([]),
                playerIsReady: $playerManager.playerIsReady,
                networkMonitor: networkMonitor,
                appleMusicSubscription: $playerManager.appleMusicSubscription
            )
        }
        .animation(.spring(), value: playerManager.currentlyPlayingSong) // Smooth show/hide
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

