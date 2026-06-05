import SwiftUI
import MusicKit
import FirebaseAnalytics

struct FavoritesView: View {
    @EnvironmentObject var favoritesManager: FavoritesManager
    
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    @Binding var navigationPath: [Route]
    @Binding var currentPlayingSong: Song?
    @Binding var isPlayingFromAlbum: Bool
    @Binding var musicAuthorized: Bool
    
    @State private var searchQuery: String = ""
    
    let albums: [Album]
    @Binding var albumCache: [MusicItemID: Album]
    
    private let bottomPlayerHeight: CGFloat = 77
    
    var filteredSongs: [Song] {
        if searchQuery.isEmpty {
            return favoritesManager.favoriteSongs
        } else {
            return favoritesManager.favoriteSongs.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.artistName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                
                // MARK: - No Internet
                if !networkMonitor.isConnected {
                    noInternetView
                    
                    // MARK: - Authorization
                } else if !musicAuthorized {
                    MusicAuthorizationView(
                        bottomPlayerHeight: bottomPlayerHeight,
                        hasPlayer: playerManager.currentlyPlayingSong != nil
                    )
                    .padding(.horizontal, 16)
                    
                    // MARK: - Empty State
                } else if favoritesManager.favoriteSongs.isEmpty {
                    emptyStateView
                    
                    // MARK: - Content
                } else {
                    contentView
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            
            // 🔥 Screen view tracking
            .onAppear {
                Analytics.logEvent("favorites_viewed", parameters: [
                    "favorite_count": favoritesManager.favoriteSongs.count
                ])
            }
            
            // 🔥 Search tracking
            .onChange(of: searchQuery) { _, newValue in
                if !newValue.isEmpty {
                    Analytics.logEvent("favorites_searched", parameters: [
                        "query": newValue
                    ])
                }
            }
            
            
            .if(networkMonitor.isConnected && musicAuthorized) { view in
                view.searchable(text: $searchQuery, prompt: "Search Favorites")
            }
            
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .album(let albumID):
                    
                    if let album = albumCache[albumID] {
                        AlbumDetailView(
                            album: album,
                            playSong: { song in
                                let songsFromFavorites = favoritesManager.favoriteSongs
                                
                                playerManager.playSong(
                                    song,
                                    from: songsFromFavorites,
                                    albumWithTracks: playerManager.albumWithTracks,
                                    playFromAlbum: true,
                                    networkMonitor: networkMonitor
                                )
                            },
                            isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                            albumWithTracks: $playerManager.albumWithTracks,
                            networkMonitor: networkMonitor,
                            playerManager: playerManager,
                            navigationPath: $navigationPath,
                            albumCache: $albumCache
                        )
                        .id(album.id)
                    } else {
                        Text("Album not found")
                    }
                    
                case .fullAlbumGrid:
                    EmptyView() // Not used in Favorites, but required
                    
                case .artist(let artistID):
                    ArtistDetailView(
                        artistID: artistID,
                        playerManager: playerManager,
                        networkMonitor: networkMonitor,
                        navigationPath: $navigationPath,
                        albumCache: $albumCache
                    )
                    
                case .fullTrackList(_, let songs, let isFromArtist):
                    FullTrackListView(
                        songs: songs,
                        playSong: { song in
                            
                            playerManager.playbackSource = .favorites
                            
                            playerManager.playSong(
                                song,
                                from: songs,
                                albumWithTracks: nil,
                                playFromAlbum: false,
                                networkMonitor: networkMonitor
                            )
                        },
                        isFromArtist: isFromArtist,
                        currentPlayingSong: $currentPlayingSong,
                        isPlayingFromAlbum: $isPlayingFromAlbum,
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                    
                case .artistAlbumGrid(let title, let albums):
                    FullAlbumGridView(
                        albums: albums,
                        title: title,
                        cacheAlbum: { album in
                            albumCache[album.id] = album
                        },
                        isFromArtist: true,   // ✅ Favorites is NOT artist-origin
                        navigationPath: $navigationPath,
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                case .recentlyPlayedGrid:
                    EmptyView() // Not used in Favorites, but required
                }
            }
            
        }
        .task {
            await favoritesManager.fetchFavoriteSongs()
        }
    }
    
    // MARK: - CONTENT VIEW
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                
                ForEach(filteredSongs, id: \.id) { song in
                    HStack(spacing: 6) {
                        
                        SongRowView(
                            song: song,
                            currentPlayingSong: $currentPlayingSong,
                            leftPadding: 8,
                            rightPadding: 0
                        )
                        
                        Button {
                            let wasFavorite = favoritesManager.isFavorite(song)
                            let removedIndex = favoritesManager.favoriteSongs.firstIndex(where: { $0.id == song.id })
                            
                            withAnimation {
                                favoritesManager.toggleFavorite(song)
                            }
                            
                            // ✅ Remove just the specific entry from queue
                            if wasFavorite && playerManager.appleMusicSubscription && playerManager.playbackSource == .favorites {
                                let player = ApplicationMusicPlayer.shared
                                
                                // Find the queue entry for the unfavorited song
                                if let entryToRemove = player.queue.entries.first(where: { entry in
                                    if case .song(let queueSong) = entry.item {
                                        return queueSong.id == song.id
                                    }
                                    return false
                                }) {
                                    // Remove it from the queue
                                    player.queue.entries.removeAll { $0.id == entryToRemove.id }
                                }
                            }
                            
                            // Handle preview mode removal
                            if wasFavorite && !playerManager.appleMusicSubscription {
                                Task { @MainActor in
                                    playerManager.handleCurrentFavoriteRemoved(
                                        removedSong: song,
                                        removedIndex: removedIndex,
                                        favoritesManager: favoritesManager,
                                        networkMonitor: networkMonitor
                                    )
                                }
                            }
                            
                            Analytics.logEvent("favorite_toggled_from_list", parameters: [
                                "song_id": song.id.rawValue,
                                "is_favorite": !wasFavorite
                            ])
                            
                        } label: {
                            Image(systemName: favoritesManager.isFavorite(song) ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .padding(.trailing, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.dismissKeyboard()
                        
                        // 🔥 Playback tracking
                        Analytics.logEvent("favorite_song_played", parameters: [
                            "song_id": song.id.rawValue,
                            "title": song.title,
                            "artist": song.artistName
                        ])
                        
                        playerManager.playbackSource = .favorites
                        
                        playerManager.playSong(
                            song,
                            from: favoritesManager.favoriteSongs,
                            albumWithTracks: nil,
                            playFromAlbum: false,
                            networkMonitor: networkMonitor
                        )
                        isPlayingFromAlbum = false
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }
    
    // MARK: - EMPTY STATE
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No Favorites Yet")
                .font(.headline)

            Text("Tap the star on any song to save it here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }
    
    // MARK: - NO INTERNET VIEW
    private var noInternetView: some View {
        VStack(spacing: 8) {
            Spacer()
            
            Text("No Internet connection")
                .font(.headline)
            
            Text("Your device is not connected to the internet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }
}
