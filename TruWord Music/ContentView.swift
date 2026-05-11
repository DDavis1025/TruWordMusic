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
    case fullAlbumGrid
    case album(Album)
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
    @State private var albums: [Album] = []

    // 🔥 Navigation Path (typed)
    @Binding var navigationPath: NavigationPath

    @Environment(\.scenePhase) private var scenePhase
    private let bottomPlayerHeight: CGFloat = 70

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

                case .fullAlbumGrid:
                    FullAlbumGridView(
                        albums: albums,
                        onAlbumSelected: { album in
                            navigationPath.append(Route.album(album))
                        },
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )

                case .album(let album):
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
                        playerManager: playerManager
                    )
                    .id(album.id)
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
                        Spacer().frame(height: 15)
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
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }

    // MARK: - Albums Section

    private var albumsSection: some View {
        if albums.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading) {
                HStack {
                    Text("Top Christian Albums")
                        .font(.system(size: 18)).bold()

                    Spacer()

                    if albums.count > 5 {
                        NavigationLink(value: Route.fullAlbumGrid) {
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
                        ForEach(albums.prefix(5), id: \.id) { album in
                            AlbumCarouselItemView(album: album)
                                .onTapGesture {
                                    navigationPath.append(Route.album(album))

                                    Analytics.logEvent("album_opened_from_carousel", parameters: [
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
        VStack(alignment: .leading) {
            HStack {
                Text("Top Christian Songs")
                    .font(.system(size: 18)).bold()

                Spacer()

                if songs.count > 5 {
                    NavigationLink {
                        FullTrackListView(
                            songs: songs,
                            playSong: { song in
                                playerManager.playbackSource = .home

                                playerManager.playSong(
                                    song,
                                    from: songs,
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

                        playerManager.playSong(
                            song,
                            from: songs,
                            albumWithTracks: nil,
                            playFromAlbum: false,
                            networkMonitor: networkMonitor
                        )

                        Analytics.logEvent("song_played_from_home", parameters: [
                            "song_name": song.title,
                            "artist": song.artistName
                        ])
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
            let fetchedAlbums = response.albumCharts.flatMap { $0.items }

            await MainActor.run {
                self.albums = fetchedAlbums
            }

        } catch {
            print("Error fetching albums: \(error)")
        }
    }
}
