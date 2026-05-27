//
//  ArtistDetailView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 5/19/26.
//


import SwiftUI
import MusicKit
import FirebaseAnalytics

struct ArtistDetailView: View {
    
    let artistID: MusicItemID
    
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor
    
    @Binding var navigationPath: [Route]
    
    @Binding var albumCache: [MusicItemID: Album]
    
    @State private var artist: Artist?
    @State private var topAlbums: [Album] = []
    @State private var topSongs: [Song] = []
    
    @State private var isLoading = true
    
    private let bottomPlayerHeight: CGFloat = 77
    
    private var appleMusicArtistURL: URL? {
        URL(string: "https://music.apple.com/us/artist/\(artistID)")
    }
    
    var body: some View {
        Group {
            
            if isLoading {
                
                VStack {
                    Spacer()
                    
                    ProgressView("Loading Artist...")
                    
                    Spacer()
                }
                
            } else {
                
                ScrollView {
                    
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // MARK: - Artist Header
                        
                        VStack(spacing: 7) {
                            
                            if let artworkURL = artist?.artwork?.url(width: 320, height: 320) {
                                CustomAsyncImage(url: artworkURL, isCircle: true)
                                    .frame(width: 160, height: 160)
                            }
                            
                            VStack(spacing: 2) {
                                Text(artist?.name ?? "")
                                    .font(.title2.bold())

                                Text("Artist")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let appleMusicArtistURL, !playerManager.appleMusicSubscription {
                                
                                HStack {
                                    Spacer()
                                    
                                    Image("AppleMusicBadge")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: min(UIScreen.main.bounds.width * 0.1, 65))
                                        .padding(.top, 14)
                                        .onTapGesture {
                                            Analytics.logEvent("apple_music_link_tapped", parameters: [
                                                "source": "artist_detail",
                                                "artist_id": artistID.rawValue,
                                                "artist_name": artist?.name ?? ""
                                            ])
                                            
                                            UIApplication.shared.open(appleMusicArtistURL)
                                        }
                                    
                                    Spacer()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top)
                        
                        // MARK: - Top Albums
                        
                        if !topAlbums.isEmpty {
                            
                            VStack(alignment: .leading) {
                                
                                HStack {
                                    
                                    Text("Top Releases")
                                        .font(.system(size: 20, weight: .bold))
                                    
                                    Spacer()
                                    
                                    if topAlbums.count > 7 {
                                        
                                        NavigationLink {
                                            FullAlbumGridView(
                                                albums: topAlbums,
                                                title: "Top Releases",
                                                cacheAlbum: { album in
                                                    albumCache[album.id] = album
                                                },
                                                navigationPath: $navigationPath,
                                                networkMonitor: networkMonitor,
                                                playerManager: playerManager
                                            )
                                            
                                        } label: {
                                            Text("View All")
                                        }
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                                    }
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    
                                    HStack(spacing: 16) {
                                        
                                        ForEach(topAlbums.prefix(7), id: \.id) { album in
                                            
                                            AlbumCarouselItemView(album: album)
                                                .onTapGesture {
                                                    albumCache[album.id] = album
                                                    navigationPath.append(.album(album.id))
                                                    Analytics.logEvent("artist_album_opened", parameters: [
                                                        "album_name": album.title,
                                                        "artist_name": artist?.name ?? ""
                                                    ])
                                                }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // MARK: - Top Songs
                        
                        if !topSongs.isEmpty {
                            
                            VStack(alignment: .leading) {
                                
                                HStack {
                                    
                                    Text("Top Songs")
                                        .font(.system(size: 20, weight: .bold))
                                    
                                    Spacer()
                                    
                                    if topSongs.count > 7 {
                                        
                                        NavigationLink {
                                            
                                            FullTrackListView(
                                                songs: topSongs,
                                                playSong: { song in
                                                    
                                                    playerManager.playbackSource = .artist
                                                    
                                                    playerManager.playSong(
                                                        song,
                                                        from: topSongs,
                                                        albumWithTracks: nil,
                                                        playFromAlbum: false,
                                                        networkMonitor: networkMonitor
                                                    )
                                                },
                                                currentPlayingSong: $playerManager.currentlyPlayingSong,
                                                isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                                                networkMonitor: networkMonitor,
                                                playerManager: playerManager
                                            )
                                            
                                        } label: {
                                            Text("View All")
                                        }
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                                    }
                                }
                                
                                VStack(spacing: 0) {
                                    
                                    ForEach(topSongs.prefix(7), id: \.id) { song in
                                        
                                        SongRowView(
                                            song: song,
                                            currentPlayingSong: $playerManager.currentlyPlayingSong
                                        )
                                        .onTapGesture {
                                            
                                            playerManager.playbackSource = .artist
                                            
                                            playerManager.playSong(
                                                song,
                                                from: topSongs,
                                                albumWithTracks: nil,
                                                playFromAlbum: false,
                                                networkMonitor: networkMonitor
                                            )
                                            
                                            Analytics.logEvent("artist_song_played", parameters: [
                                                "song_name": song.title,
                                                "artist_name": song.artistName
                                            ])
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom,
                        playerManager.currentlyPlayingSong != nil
                        ? bottomPlayerHeight
                        : 0
                    )
                }
            }
        }
        .navigationTitle(artist?.name ?? "Artist")
        .navigationBarTitleDisplayMode(.inline)
        
        .task {
            await fetchArtistData()
        }
        
        .onAppear {
            Analytics.logEvent("artist_viewed", parameters: [
                "artist_name": artist?.name ?? ""
            ])
        }
    }
    
    // MARK: - Fetch Artist Data
    
    private func fetchArtistData() async {
        
        do {
            
            var request = MusicCatalogResourceRequest<Artist>(
                matching: \.id,
                equalTo: artistID
            )
            
            request.properties = [
                .albums,
                .topSongs
            ]
            
            request.limit = 1
            
            let response = try await request.response()
            
            guard let fetchedArtist = response.items.first else {
                
                await MainActor.run {
                    isLoading = false
                }
                
                return
            }
            
            await MainActor.run {
                
                self.artist = fetchedArtist
                
                self.topAlbums = Array(fetchedArtist.albums ?? []).filter {
                    
                    ($0.genreNames.contains("Christian") ||
                     $0.genreNames.contains("Christian & Gospel")) &&
                    
                    $0.contentRating != .explicit
                }
                
                self.topSongs = Array(fetchedArtist.topSongs ?? []).filter {
                    
                    ($0.genreNames.contains("Christian") ||
                     $0.genreNames.contains("Christian & Gospel")) &&
                    
                    $0.contentRating != .explicit
                }
                
                self.isLoading = false
            }
            
        } catch {
            
            print("Error fetching artist: \(error)")
            
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
