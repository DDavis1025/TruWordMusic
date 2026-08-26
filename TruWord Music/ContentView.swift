import SwiftUI
import MusicKit
import AVFoundation
import FirebaseAnalytics

// MARK: - Models

struct AlbumWithTracks {
    var album: Album
    var tracks: [Song]
}

struct MoreByArtistSection {
    let artist: Artist
    let albums: [Album]
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
    @State private var moreByArtistSection: MoreByArtistSection?
    @State private var recommendedAlbums: [Album] = []
    @State private var recommendedFromAlbum: Album?
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
                    await loadMoreByArtist()
                    await loadPersonalizedRecommendations()
                }

                isLoading = false
            }
            
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await checkAppleMusicStatus()
                    }
                }
            }

            .onChange(of: playerManager.artistPlayCounts) { _, _ in
                Task {
                    await loadMoreByArtist()
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
                        recommendedAlbumsSection
                        moreByArtistSectionView
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
            let items = Array(playerManager.recentlyPlayedAlbums.prefix(10))

            VStack(alignment: .leading) {

                HStack(spacing: 4) {
                    Text("Recently Played")
                        .font(.system(size: 18, weight: .bold))

                    if playerManager.recentlyPlayedAlbums.count >= 10 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.gray)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard playerManager.recentlyPlayedAlbums.count > 10 else { return }

                    navigationPath.append(
                        .recentlyPlayedGrid(source: "recently_played")
                    )
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
            .padding(.bottom, 25)
        }
    }
    
    // MARK: - Albums Section
    
    private var albumsSection: some View {
        if albums.isEmpty { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Top Christian Albums")
                        .font(.system(size: 18, weight: .bold))

                    if albums.count >= 10 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.gray)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard albums.count > 10 else { return }

                    navigationPath.append(
                        .fullAlbumGrid(source: "home_top_christian_albums")
                    )

                    Analytics.logEvent("view_more_albums", parameters: nil)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(albums.prefix(10), id: \.id) { album in
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
                .padding(.bottom, 25)
        )
    }
    
    // MARK: - Songs Section
    
    private var songsSection: some View {
        if songs.isEmpty { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Top Christian Songs")
                        .font(.system(size: 18, weight: .bold))

                    if songs.count > 7 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.gray)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard songs.count > 7 else { return }

                    navigationPath.append(
                        .fullTrackList(
                            title: "Top Songs",
                            songs: songs,
                            isFromArtist: false
                        )
                    )

                    Analytics.logEvent("view_more_songs", parameters: nil)
                }
                
                ForEach(songs.prefix(7), id: \.id) { song in
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
    
    @ViewBuilder
    private var moreByArtistSectionView: some View {
        if let section = moreByArtistSection,
           !section.albums.isEmpty {

            VStack(alignment: .leading, spacing: 12) {

                HStack(spacing: 4) {

                    Text("More By \(section.artist.name)")
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if section.albums.count >= 10 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.gray)
                    }

                    Spacer()
                }
                .padding(.leading, 0)
                .padding(.trailing, 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard section.albums.count > 10 else { return }

                    navigationPath.append(
                        .artistAlbumGrid(
                            title: section.artist.name,
                            albums: section.albums,
                            showAlbumYear: true,
                            source: "more_by_artist_home"
                        )
                    )

                    Analytics.logEvent("more_by_artist_view_more", parameters: [
                        "artist_id": section.artist.id.rawValue,
                        "artist_name": section.artist.name
                    ])
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(section.albums.prefix(10), id: \.id) { album in
                            AlbumCarouselItemView(
                                album: album,
                                showAlbumYear: true
                            )
                            .onTapGesture {
                                albumCache[album.id] = album
                                navigationPath.append(.album(album.id))

                                Analytics.logEvent("more_by_album_opened", parameters: [
                                    "album_id": album.id.rawValue,
                                    "album_title": album.title,
                                    "artist_id": section.artist.id.rawValue,
                                    "artist_name": section.artist.name,
                                    "source": "home_more_by_artist"
                                ])
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 25)
        }
    }
    
    private func mostPlayedArtistID() -> String? {
        playerManager.artistPlayCounts.max {
            $0.value < $1.value
        }?.key
    }
    
    private func loadMoreByArtist() async {
        guard let artistIDString = mostPlayedArtistID() else {
            await MainActor.run {
                moreByArtistSection = nil
            }
            return
        }

        do {
            let artistID = MusicItemID(artistIDString)

            // Resolve the actual artist directly by ID.
            var artistRequest = MusicCatalogResourceRequest<Artist>(
                matching: \.id,
                equalTo: artistID
            )

            artistRequest.properties = [.albums]
            artistRequest.limit = 1

            let artistResponse = try await artistRequest.response()

            guard let fullArtist = artistResponse.items.first else {
                return
            }

            let filteredAlbums = (fullArtist.albums ?? []).filter { album in
                let isChristian =
                    album.genreNames.contains("Christian") ||
                    album.genreNames.contains("Christian & Gospel")

                let isNotExplicit = album.contentRating != .explicit

                return isChristian && isNotExplicit
            }

            await MainActor.run {
                moreByArtistSection = MoreByArtistSection(
                    artist: fullArtist,
                    albums: filteredAlbums
                )

                for album in filteredAlbums {
                    albumCache[album.id] = album
                }
            }

        } catch {
            print("Failed to load More By Artist: \(error)")

            await MainActor.run {
                moreByArtistSection = nil
            }
        }
    }
    
    @ViewBuilder
    private var recommendedAlbumsSection: some View {
        if !recommendedAlbums.isEmpty,
           let sourceAlbum = recommendedFromAlbum {

            VStack(alignment: .leading, spacing: 12) {

                HStack(spacing: 4) {

                    Text("You Might Also Like")
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if recommendedAlbums.count >= 10 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.gray)
                    }

                    Spacer()
                }
                .padding(.leading, 0)
                .padding(.trailing, 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard recommendedAlbums.count >= 10 else { return }

                    navigationPath.append(
                        .artistAlbumGrid(
                            title: "You Might Also Like",
                            albums: recommendedAlbums,
                            showAlbumYear: false,
                            source: "you_might_also_like"
                        )
                    )

                    Analytics.logEvent("recommended_albums_view_more", parameters: [
                        "album_count": recommendedAlbums.count,
                        "source_album_id": sourceAlbum.id.rawValue,
                        "source_album_title": sourceAlbum.title
                    ])
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {

                        ForEach(
                            recommendedAlbums.prefix(10),
                            id: \.id
                        ) { album in

                            AlbumCarouselItemView(
                                album: album,
                                showAlbumYear: false
                            )
                            .onTapGesture {
                                albumCache[album.id] = album
                                navigationPath.append(.album(album.id))

                                Analytics.logEvent(
                                    "recommended_album_opened_home",
                                    parameters: [
                                        "album_id": album.id.rawValue,
                                        "album_title": album.title,
                                        "source_album_id": sourceAlbum.id.rawValue,
                                        "source_album_title": sourceAlbum.title
                                    ]
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 25)
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
    
    private func loadPersonalizedRecommendations() async {
        // Sort all played albums from most played → least played.
        let rankedAlbumIDs = playerManager.albumPlayCounts
            .sorted { $0.value > $1.value }
            .map { $0.key }

        guard !rankedAlbumIDs.isEmpty else {
            await MainActor.run {
                recommendedAlbums = []
                recommendedFromAlbum = nil
            }
            return
        }

        // Try each album in play-count order until we find
        // one with valid related albums.
        for albumIDString in rankedAlbumIDs {
            do {
                let albumID = MusicItemID(albumIDString)

                var request = MusicCatalogResourceRequest<Album>(
                    matching: \.id,
                    equalTo: albumID
                )

                request.properties = [.relatedAlbums]
                request.limit = 1

                let response = try await request.response()

                guard let album = response.items.first else {
                    continue
                }

                let filtered = (album.relatedAlbums ?? []).filter { album in
                    let isChristian =
                        album.genreNames.contains("Christian") ||
                        album.genreNames.contains("Christian & Gospel")

                    let isNotExplicit = album.contentRating != .explicit

                    return isChristian && isNotExplicit
                }

                // If this album has valid recommendations, use them.
                if !filtered.isEmpty {
                    await MainActor.run {
                        recommendedFromAlbum = album
                        recommendedAlbums = filtered

                        // Cache them for navigation.
                        for album in filtered {
                            albumCache[album.id] = album
                        }
                    }

                    print("You Might Also Like source: \(album.title)")
                    print("Recommendations found: \(filtered.count)")

                    return
                }

                // Otherwise, continue to the next most-played album.
                print("No recommendations for: \(album.title)")

            } catch {
                print("Failed to load recommendations for album \(albumIDString): \(error)")
                continue
            }
        }

        // None of the played albums had recommendations.
        await MainActor.run {
            recommendedAlbums = []
            recommendedFromAlbum = nil
        }

        print("No recommendations found for any played album.")
    }
}
