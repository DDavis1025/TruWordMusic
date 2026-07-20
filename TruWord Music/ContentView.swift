import SwiftUI
import MusicKit
import AVFoundation
import FirebaseAnalytics

// MARK: - Models

struct AlbumWithTracks {
    var album: Album
    var tracks: [Song]
}

// MARK: - Route

enum Route: Hashable {
    case fullAlbumGrid(source: String)
    case fullTrackList(title: String, songs: [Song], isFromArtist: Bool)
    case artistAlbumGrid(
        title: String,
        albums: [Album],
        showAlbumYear: Bool,
        source: String
    )
    case album(MusicItemID)
    case artist(MusicItemID)
    case recentlyPlayedGrid(source: String)
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor
    @StateObject private var verseManager = DailyVerseManager()
    @StateObject private var songOfDayManager = SongOfTheDayManager()
    
    // Authorization & Data
    @Binding var musicAuthorized: Bool
    @State private var hasRequestedMusicAuthorization = false
    @State private var isLoading = false
    
    // Songs & Albums
    @State private var songs: [Song] = []
    @Binding var albums: [Album]
    @Binding var albumCache: [MusicItemID: Album]
    
    @Binding var navigationPath: [Route]
    
    @Environment(\.scenePhase) private var scenePhase
    private let bottomPlayerHeight: CGFloat = 77
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !networkMonitor.isConnected && !isLoading {
                    noInternetView
                    
                } else if isLoading || !hasRequestedMusicAuthorization {
                    ZStack {
                        ProgressView("Loading...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, playerManager.currentlyPlayingSong != nil ? bottomPlayerHeight : 0)
                } else {
                    mainContent
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            
            // 🔥 Typed navigation
            .navigationDestination(for: Route.self) { route in
                switch route {
                    
                case .fullAlbumGrid(let source):
                    FullAlbumGridView(
                        albums: albums,
                        title: "Top Albums",
                        cacheAlbum: { album in
                            albumCache[album.id] = album
                        },
                        isFromArtist: false,
                        showAlbumYear: false,
                        source: source,
                        navigationPath: $navigationPath,
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                    
                case .album(let albumID):
                    
                    if let album = albumCache[albumID] {
                        AlbumDetailView(
                            album: album,
                            playSong: { song in
                                playerManager.playbackSource = .album
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
                            playerManager: playerManager,
                            navigationPath: $navigationPath,
                            albumCache: $albumCache
                        )
                        .id(album.id)
                    } else {
                        EmptyView()
                    }
                    
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
                            playerManager.playbackSource = isFromArtist ? .artist : .home
                            
                            playerManager.playSong(
                                song,
                                from: songs,
                                albumWithTracks: nil,
                                playFromAlbum: false,
                                networkMonitor: networkMonitor
                            )
                        },
                        isFromArtist: isFromArtist,
                        currentPlayingSong: $playerManager.currentlyPlayingSong,
                        isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                case .artistAlbumGrid(let title, let albums, let showAlbumYear, let source):
                    FullAlbumGridView(
                        albums: albums,
                        title: title,
                        cacheAlbum: { album in
                            albumCache[album.id] = album
                        },
                        isFromArtist: true,
                        showAlbumYear: showAlbumYear,
                        source: source,
                        navigationPath: $navigationPath,
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                case .recentlyPlayedGrid(let source):
                    FullAlbumGridView(
                        albums: playerManager.recentlyPlayedAlbums.compactMap {
                            albumCache[MusicItemID($0.id)]
                        },
                        title: "Recently Played",
                        cacheAlbum: { album in
                            albumCache[album.id] = album
                        },
                        isFromArtist: false,
                        showAlbumYear: false,
                        source: source,
                        navigationPath: $navigationPath,
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                    .onAppear {
                            Analytics.logEvent("recently_played_grid_viewed", parameters: [
                                "album_count": playerManager.recentlyPlayedAlbums.count
                            ])
                        }
                }
            }
            
            .onAppear {
                Analytics.logEvent("home_viewed", parameters: nil)
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

                    await loadRecentlyPlayedAlbumsIntoCache()
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
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        Group {
            if musicAuthorized {
                ScrollView {
                    VStack {
                        TodaySectionView(
                            verseManager: verseManager,
                            songOfDayManager: songOfDayManager,
                            playerManager: playerManager,
                            songs: songs
                        )
                        Spacer().frame(height: 20)
                        recentlyPlayedAlbums
                        albumsSection
                        songsSection
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                ZStack {
                    MusicAuthorizationView(
                        bottomPlayerHeight: bottomPlayerHeight,
                        hasPlayer: playerManager.currentlyPlayingSong != nil
                    )
                    .padding(.horizontal, 16)
                    
                    VStack {
                        TodaySectionView(
                            verseManager: verseManager,
                            songOfDayManager: songOfDayManager,
                            playerManager: playerManager,
                            songs: songs
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }
    
    // MARK: - No Internet View
    
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
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }
    
    @ViewBuilder
    private var recentlyPlayedAlbums: some View {
        if !playerManager.recentlyPlayedAlbums.isEmpty {
            let items = Array(playerManager.recentlyPlayedAlbums.prefix(7))

            VStack(alignment: .leading) {

                HStack {
                    Text("Recently Played")
                        .font(.system(size: 18, weight: .bold))

                    Spacer()

                    if playerManager.recentlyPlayedAlbums.count > 7 {
                        NavigationLink(
                            value: Route.recentlyPlayedGrid(source: "recently_played")
                        ) {
                            Text("View More")
                                .font(.system(size: 15))
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(items) { item in
                            if let album = albumCache[MusicItemID(item.id)] {
                                AlbumCarouselItemView(album: album)
                                    .onTapGesture {
                                        navigationPath.append(.album(album.id))
                                        
                                        Analytics.logEvent("album_opened", parameters: [
                                                "album_id": album.id.rawValue,
                                                "album_name": album.title,
                                                "artist_name": album.artistName,
                                                "source": "recently_played"
                                            ])
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 14)
        }
    }
    
    // MARK: - Albums Section
    
    private var albumsSection: some View {
        if albums.isEmpty { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading) {
                HStack {
                    Text("Top Christian Albums")
                        .font(.system(size: 18, weight: .bold))
                    
                    Spacer()
                    
                    if albums.count > 7 {
                        NavigationLink(
                            value: Route.fullAlbumGrid(source: "home_top_christian_albums")
                        ) {
                            Text("View More")
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            Analytics.logEvent("view_more_albums", parameters: nil)
                        })
                        .foregroundColor(.blue)
                        .font(.system(size: 15))
                    }
                }
                .padding(.vertical, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(albums.prefix(7), id: \.id) { album in
                            AlbumCarouselItemView(album: album)
                                .onTapGesture {
                                    navigationPath.append(.album(album.id))
                                    
                                    Analytics.logEvent("album_opened_from_carousel", parameters: [
                                        "album_id:" : album.id,
                                        "album_name": album.title
                                    ])
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
                .padding(.bottom, 14)
        )
    }
    
    // MARK: - Songs Section
    
    private var songsSection: some View {
        if songs.isEmpty { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading) {
                HStack {
                    Text("Top Christian Songs")
                        .font(.system(size: 18, weight: .bold))
                    
                    Spacer()
                    
                    if songs.count > 5 {
                        NavigationLink(
                            value: Route.fullTrackList(
                                title: "Top Songs",
                                songs: songs,
                                isFromArtist: false
                            )
                        ) {
                            Text("View More")
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            Analytics.logEvent("view_more_songs", parameters: nil)
                        })
                        .foregroundColor(.blue)
                        .font(.system(size: 15))
                    }
                }
                .padding(.vertical, 4)
                
                ForEach(songs.prefix(5), id: \.id) { song in
                    SongRowView(song: song, currentPlayingSong: $playerManager.currentlyPlayingSong)
                        .onTapGesture {
            
                            playerManager.playbackSource = .home
                            playerManager.isPlayingFromAlbum = false
                            
                            playerManager.playSong(
                                song,
                                from: songs,
                                albumWithTracks: nil,
                                playFromAlbum: false,
                                networkMonitor: networkMonitor
                            )
                            
                            Analytics.logEvent("song_played_from_home", parameters: [
                                "song_id": song.id,
                                "song_name": song.title,
                                "artist": song.artistName
                            ])
                        }
                }
            }
        )
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
        let christianGenreID = MusicItemID("22")
        
        var request = MusicCatalogResourceRequest<Genre>(
            matching: \.id,
            equalTo: christianGenreID
        )
        
        request.limit = 1
        
        return try await request.response().items.first
    }
    
    private func fetchChristianSongs() async {
        do {
            guard let genre = try await fetchChristianGenre() else { return }
            
            var request = MusicCatalogChartsRequest(
                genre: genre,
                types: [Song.self]
            )
            
            request.limit = 70
            
            let fetchedSongs = (try await request.response())
                .songCharts
                .flatMap { $0.items }
                .filter { $0.contentRating != .explicit }
            
            await MainActor.run {
                self.songs = fetchedSongs
                self.playerManager.songs = fetchedSongs
                
                songOfDayManager.loadSongs(fetchedSongs)
            }
            
        } catch {
            print("Error fetching songs: \(error)")
        }
    }
    
    private func fetchChristianAlbums() async {
        do {
            guard let genre = try await fetchChristianGenre() else { return }
            
            var request = MusicCatalogChartsRequest(
                genre: genre,
                types: [Album.self]
            )
            
            request.limit = 70
            
            let response = try await request.response()
            let fetchedAlbums = response.albumCharts
                .flatMap { $0.items }
                .filter { $0.contentRating != .explicit }
            
            await MainActor.run {
                
                self.albums = fetchedAlbums
                // also push into cache
                for album in fetchedAlbums {
                    albumCache[album.id] = album
                }
                
            }
            
        } catch {
            print("Error fetching albums: \(error)")
        }
    }
    
    private func loadRecentlyPlayedAlbumsIntoCache() async {
        for item in playerManager.recentlyPlayedAlbums {

            let albumID = MusicItemID(item.id)

            // Skip albums already cached
            if albumCache[albumID] != nil {
                continue
            }

            do {
                var request = MusicCatalogResourceRequest<Album>(
                    matching: \.id,
                    equalTo: albumID
                )

                request.limit = 1

                if let album = try await request.response().items.first {
                    await MainActor.run {
                        albumCache[album.id] = album
                    }
                }

            } catch {
                print("Failed to load album \(item.id): \(error)")
            }
        }
    }
}
