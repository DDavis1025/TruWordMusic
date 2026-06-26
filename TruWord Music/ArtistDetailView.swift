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
    @State private var similarArtists: [Artist] = []
    
    @State private var isLoading = true
    
    private let bottomPlayerHeight: CGFloat = 77
    
    private var appleMusicArtistURL: URL? {
        AppleMusicAffiliateManager.makeURL(type: .artist, id: artistID)
    }
    
    var body: some View {
        Group {
            
            if isLoading {
                
                ZStack {
                    ProgressView("Loading...")
                }
                .padding(.bottom, playerManager.currentlyPlayingSong != nil ? bottomPlayerHeight : 0)
                
            } else if !networkMonitor.isConnected {
                VStack(spacing: 8) {
                    Spacer()
                    
                    Text("No Internet connection")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("Your device is not connected to the internet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            } else {
                
                ScrollView {
                    
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // MARK: - Artist Header
                        
                        VStack(spacing: 7) {
                            let displaySize: CGFloat = 160
                            let scale = UIScreen.main.scale
                            let pixelSize = Int(displaySize * scale * 2) // extra sharp (2x retina)
                            let artworkURL = artist?.artwork?.url(width: pixelSize, height: pixelSize)
                            
                            CustomAsyncImage(url: artworkURL, isCircle: true)
                                .frame(width: 160, height: 160)
                            
                            VStack(spacing: 2) {
                                Text(artist?.name ?? "")
                                    .font(.title2.bold())
                                
                                Text("Artist")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            
                            if let appleMusicArtistURL, !playerManager.appleMusicSubscription {
                                
                                HStack {
                                    Spacer()
                                    
                                    Image("AppleMusicBadge")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: min(UIScreen.main.bounds.width * 0.1, 65))
                                        .padding(.top, 20.2)
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
                            if !isLoading && topAlbums.isEmpty && topSongs.isEmpty {
                                Text("No Christian music available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 35)
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
                                        
                                        NavigationLink(
                                            value: Route.artistAlbumGrid(
                                                title: "Top Releases",
                                                albums: topAlbums
                                            )
                                        ) {
                                            Text("View More")
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
                                                    // Cache the album immediately
                                                    albumCache[album.id] = album
                                                    
                                                    // 🔥 NEW: pre-warm album tracks in background
                                                    Task {
                                                        _ = await prefetchAlbumTracks(album: album)
                                                    }
                                                    
                                                    navigationPath.append(.album(album.id))
                                                    
                                                    Analytics.logEvent("artist_album_opened_from_carousel", parameters: [
                                                        "album_name": album.title,
                                                        "artist_id": artistID.rawValue,
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
                                    
                                    if topSongs.count > 10 {
                                        NavigationLink(
                                            value: Route.fullTrackList(
                                                title: "Top Songs",
                                                songs: topSongs,
                                                isFromArtist: true
                                            )
                                        ) {
                                            Text("View More")
                                        }
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                                    }
                                }
                                
                                VStack(spacing: 0) {
                                    
                                    ForEach(topSongs.prefix(10), id: \.id) { song in
                                        
                                        SongRowView(
                                            song: song,
                                            currentPlayingSong: $playerManager.currentlyPlayingSong
                                        )
                                        .onTapGesture {
                                            
                                            playerManager.playbackSource = .artist
                                            playerManager.isPlayingFromAlbum = false
                                            
                                            playerManager.playSong(
                                                song,
                                                from: topSongs,
                                                albumWithTracks: nil,
                                                playFromAlbum: false,
                                                networkMonitor: networkMonitor
                                            )
                                            
                                            Analytics.logEvent("song_played_from_artist_detail", parameters: [
                                                "song_name": song.title,
                                                "artist_id": artistID.rawValue,
                                                "artist_name": song.artistName
                                            ])
                                        }
                                    }
                                }
                            }
                        }
                        // MARK: - Similar Artists
                        if !similarArtists.isEmpty {
                            
                            VStack(alignment: .leading) {
                                
                                HStack {
                                    Text("Similar Artists")
                                        .font(.system(size: 20, weight: .bold))
                                    Spacer()
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    
                                    HStack(spacing: 16) {
                                        
                                        ForEach(similarArtists, id: \.id) { artist in
                                            SimilarArtistCarouselItemView(artist: artist)
                                                .onTapGesture {
                                                    navigationPath.append(.artist(artist.id))
                                                    
                                                    Analytics.logEvent("similar_artist_opened", parameters: [
                                                        "artist_id": artist.id.rawValue,
                                                        "artist_name": artist.name
                                                    ])
                                                }
                                        }
                                    }
                                    .padding(.leading, 8)
                                    .padding(.trailing, 16)
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if networkMonitor.isConnected {
                    ShareLink(
                        item: appleMusicArtistURL ?? URL(string: "https://apps.apple.com/app/id6744539952")!
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if let artist {
                                Analytics.logEvent("share_sheet_opened", parameters: [
                                    "artist_id": artist.id.rawValue,
                                    "artist_name": artist.name,
                                    "source": "artist_detail"
                                ])
                            }
                        }
                    )
                }
            }
        }
        
        .task {
            await fetchArtistData()
        }
        
        .onAppear {
            Analytics.logEvent("artist_viewed", parameters: [
                "artist_name": artist?.name ?? ""
            ])
        }
    }
    
    private func prefetchAlbumTracks(album: Album) async -> [Song] {
        do {
            var albumRequest = MusicCatalogResourceRequest<Album>(
                matching: \.id,
                equalTo: album.id
            )
            
            albumRequest.properties = [.tracks]
            
            let albumResponse = try await albumRequest.response()
            
            guard let fetchedAlbum = albumResponse.items.first,
                  let albumTracks = fetchedAlbum.tracks else {
                return []
            }
            
            let trackIDs = albumTracks.compactMap { $0.id }
            
            let songsRequest = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                memberOf: trackIDs
            )
            
            let songResponse = try await songsRequest.response()
            
            return Array(songResponse.items)
            
        } catch {
            print("Error pre-fetching album tracks: \(error)")
            return []
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
                .topSongs,
                .similarArtists
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
                
                self.topAlbums = Array(fetchedArtist.albums ?? [])
                    .filter {
                        ($0.genreNames.contains("Christian") ||
                         $0.genreNames.contains("Christian & Gospel")) &&
                        $0.contentRating != .explicit
                    }
                    .sorted {
                        ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
                    }
                
                self.topSongs = Array(fetchedArtist.topSongs ?? [])
                    .filter {
                        ($0.genreNames.contains("Christian") ||
                         $0.genreNames.contains("Christian & Gospel")) &&
                        $0.contentRating != .explicit
                    }
                    .sorted {
                        ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
                    }
                
                self.similarArtists = Array(fetchedArtist.similarArtists ?? []).filter { artist in
                    let hasChristianAlbum = (artist.albums ?? []).contains {
                        $0.genreNames.contains("Christian") ||
                        $0.genreNames.contains("Christian & Gospel") &&
                       $0.contentRating != .explicit
                    }
                    
                    let hasChristianSong = (artist.topSongs ?? []).contains {
                        $0.genreNames.contains("Christian") ||
                        $0.genreNames.contains("Christian & Gospel") &&
                        $0.contentRating != .explicit
                    }
                    
                    return hasChristianAlbum || hasChristianSong
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
