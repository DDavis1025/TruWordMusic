//
//  ContentView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 1/31/25.
//

import SwiftUI
import MusicKit
import AVFoundation

// MARK: - Main ContentView

struct AlbumWithTracks {
    var album: Album
    var tracks: [Song]
}

struct ContentView: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor
    
    // Authorization & Data
    @State private var musicAuthorized = false
    @State private var hasRequestedMusicAuthorization = false
    @State private var isLoading = false
    
    // Songs & Albums
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    
    // UI State
    @Binding var navigationPath: NavigationPath // shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    private let bottomPlayerHeight: CGFloat = 60
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !networkMonitor.isConnected && !isLoading {
                    noInternetView
                } else if isLoading || !hasRequestedMusicAuthorization {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                } else {
                    mainScrollView
                }
            }
            .navigationDestination(for: String.self) { value in
                if value == "fullAlbumGrid" {
                    FullAlbumGridView(
                        albums: albums,
                        onAlbumSelected: {
                            album in navigationPath.append(album)
                        },
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                }
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(
                    album: album,
                    playSong: { song in
                        playerManager.playSong(
                            song,
                            from: songs,
                            albumWithTracks: playerManager.albumWithTracks,
                            playFromAlbum: true,
                            networkMonitor: networkMonitor
                        )
                    },
                    isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                    albumWithTracks: $playerManager.albumWithTracks,
                    networkMonitor: networkMonitor,
                    playerManager: playerManager
                )
                .id(album.id)
            }
            .task {
                isLoading = true
                await requestMusicAuthorization()
                if musicAuthorized {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await checkAppleMusicStatus() }
                        group.addTask { await fetchChristianSongs() }
                        group.addTask { await fetchChristianAlbums() }
                    }
                }
                isLoading = false
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await checkAppleMusicStatus() }
                }
            }
        }
    }
    
    
    
    // MARK: - UI
    
    private var noInternetView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No Internet connection")
                .font(.headline)
                .foregroundColor(.black)
            Text("Your device is not connected to the internet")
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight) // leave space for BottomPlayerView
            }
        }
    }
    
    private var mainScrollView: some View {
        ScrollView {
            VStack {
                if musicAuthorized {
                    albumsSection
                    songsSection
                } else {
                    Text("Please allow Apple Music access to continue using this app.")
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("Enable in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, playerManager.currentlyPlayingSong != nil ? bottomPlayerHeight : 0)
        }
    }
    
    private var albumsSection: some View {
        if albums.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading) {
                HStack {
                    Text("Top Christian Albums")
                        .font(.system(size: 18)).bold()
                    Spacer()
                    if albums.count > 5 {
                        NavigationLink("View More", value: "fullAlbumGrid")
                            .foregroundColor(.blue)
                            .font(.system(size: 15))
                    }
                }
                .padding(.vertical, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(albums.prefix(5), id: \.id) { album in
                            AlbumCarouselItemView(album: album)
                                .onTapGesture {
                                    DispatchQueue.main.async {
                                        navigationPath.append(album)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
                .padding(.bottom, 16)
        )
    }
    
    private var songsSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Top Christian Songs")
                    .font(.system(size: 18)).bold()
                Spacer()
                if songs.count > 5 {
                    NavigationLink("View More") {
                        FullTrackListView(
                            songs: songs,
                            playSong: { song in
                                playerManager.playSong(song, from: songs, networkMonitor: networkMonitor)
                            },
                            currentPlayingSong: $playerManager.currentlyPlayingSong,
                            isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                            networkMonitor: networkMonitor,
                            playerManager: playerManager
                        )
                    }
                    .foregroundColor(.blue)
                    .font(.system(size: 15))
                }
            }
            .padding(.vertical, 4)
            
            ForEach(songs.prefix(5), id: \.id) { song in
                SongRowView(song: song, currentPlayingSong: $playerManager.currentlyPlayingSong)
                    .onTapGesture {
                        playerManager.playSong(song, from: songs)
                        playerManager.isPlayingFromAlbum = false
                    }
            }
        }
    }
    
    
    // MARK: - MusicKit
    
    private func requestMusicAuthorization() async {
        let status = await MusicAuthorization.request()
        musicAuthorized = (status == .authorized)
        hasRequestedMusicAuthorization = true
    }
    
    private func checkAppleMusicStatus() async {
        do {
            let subscription = try await MusicSubscription.current
            playerManager.appleMusicSubscription = subscription.canPlayCatalogContent
        } catch {
            playerManager.appleMusicSubscription = false
        }
    }
    
    private func fetchChristianGenre() async throws -> Genre? {
        let christianGenreID = MusicItemID("22") // Christian & Gospel
        var request = MusicCatalogResourceRequest<Genre>(matching: \.id, equalTo: christianGenreID)
        request.limit = 1
        return try await request.response().items.first
    }
    
    private func fetchChristianSongs() async {
        do {
            guard let genre = try await fetchChristianGenre() else { return }
            var request = MusicCatalogChartsRequest(genre: genre, types: [Song.self])
            request.limit = 50
            let fetchedSongs = (try await request.response()).songCharts.flatMap { $0.items }
            
            await MainActor.run {
                self.songs = fetchedSongs              // ContentView state
                self.playerManager.songs = fetchedSongs // push to PlayerManager
            }
        } catch { print("Error fetching songs: \(error)") }
    }
    
    private func fetchChristianAlbums() async {
        do {
            guard let genre = try await fetchChristianGenre() else { return }
            var request = MusicCatalogChartsRequest(genre: genre, types: [Album.self])
            request.limit = 50
            albums = (try await request.response()).albumCharts.flatMap { $0.items }
        } catch { print("Error fetching albums: \(error)") }
    }
}

