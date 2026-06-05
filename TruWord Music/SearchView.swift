import SwiftUI
import MusicKit
import FirebaseAnalytics

enum RecentSearchItem: Identifiable, Codable, Equatable {
    case song(id: MusicItemID, title: String, artist: String, artworkURL: URL?)
    case album(id: MusicItemID, title: String, artist: String, artworkURL: URL?)
    case artist(id: MusicItemID, name: String, artworkURL: URL?)
    
    var id: String {
        switch self {
        case .song(let id, _, _, _): return id.rawValue
        case .album(let id, _, _, _): return id.rawValue
        case .artist(let id, _, _): return id.rawValue
        }
    }
}

// MARK: - Unified Result Model
enum SearchResultItem: Identifiable {
    case song(Song)
    case album(Album)
    case artist(Artist)
    
    var id: MusicItemID {
        switch self {
        case .song(let song):
            return song.id
            
        case .album(let album):
            return album.id
            
        case .artist(let artist):
            return artist.id
        }
    }
    
    var title: String {
        switch self {
        case .song(let song):
            return song.title
            
        case .album(let album):
            return album.title
            
        case .artist(let artist):
            return artist.name
        }
    }
    
    var artistName: String {
        switch self {
        case .song(let song):
            return "Song | \(song.artistName)"
            
        case .album(let album):
            return "Album | \(album.artistName)"
            
        case .artist:
            return "Artist"
        }
    }
    
    var artworkURL: URL? {
        let baseSize: CGFloat = 60 // matches your SongRowLikeView image frame
        let scale = UIScreen.main.scale
        let pixelSize = Int(baseSize * scale * 2)

        switch self {
        case .song(let song):
            return song.artwork?.url(width: pixelSize, height: pixelSize)

        case .album(let album):
            return album.artwork?.url(width: pixelSize, height: pixelSize)

        case .artist(let artist):
            return artist.artwork?.url(width: pixelSize, height: pixelSize)
        }
    }
}

// MARK: - Tab Selection Enum
enum SearchTab: String, CaseIterable, Identifiable {
    case all = "All"
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    
    var id: String { rawValue }
}

struct SearchView: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var keyboardObserver: KeyboardObserver
    @Binding var navigationPath: [Route]
    @Binding var musicAuthorized: Bool
    
    @AppStorage("recent_searches") private var recentSearchData: Data = Data()
    @State private var recentSearches: [RecentSearchItem] = []
    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResultItem] = []
    @State private var isSearching: Bool = false
    @State private var selectedTab: SearchTab = .all
    @State private var showClearRecentAlert = false
    
    @FocusState private var isSearchFocused: Bool
    
    @Binding var albumCache: [MusicItemID: Album]
    
    let albums: [Album]
    
    @Namespace private var tabNamespace
    
    private let bottomPlayerHeight: CGFloat = 77
    
    private var shouldShowRecentSearches: Bool {
        searchQuery.isEmpty && searchResults.isEmpty
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !networkMonitor.isConnected {
                    noInternetView
                    
                } else if !musicAuthorized {
                    MusicAuthorizationView(
                        bottomPlayerHeight: bottomPlayerHeight,
                        hasPlayer: playerManager.currentlyPlayingSong != nil
                    )
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 0) {
                        
                        // MARK: - Tab Bar
                        if !shouldShowRecentSearches {
                            HStack(spacing: 0) {
                                ForEach(SearchTab.allCases) { tab in
                                    Button {
                                        withAnimation(.spring()) {
                                            selectedTab = tab
                                        }
                                        
                                        Analytics.logEvent("search_tab_changed", parameters: [
                                            "tab": tab.rawValue
                                        ])
                                    } label: {
                                        Text(tab.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(
                                                ZStack {
                                                    if selectedTab == tab {
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color(.systemGray6))
                                                            .matchedGeometryEffect(id: "tabHighlight", in: tabNamespace)
                                                    }
                                                }
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                            
                            Divider()
                        }
                        
                        // MARK: - Content
                        if isSearching {
                            ProgressView("Searching…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.bottom,
                                         playerManager.currentlyPlayingSong != nil && !keyboardObserver.isKeyboardVisible
                                         ? bottomPlayerHeight
                                         : 0
                                )
                            
                        } else if shouldShowRecentSearches {
                            recentSearchView
                        } else if filteredResults.isEmpty && !searchQuery.isEmpty {
                            VStack {
                                Spacer()
                                
                                Text("No results found")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            .padding(.bottom,
                                     playerManager.currentlyPlayingSong != nil && !keyboardObserver.isKeyboardVisible
                                     ? bottomPlayerHeight
                                     : 0
                            )
                            
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView(.vertical, showsIndicators: true) {
                                    VStack(spacing: 0) {
                                        ForEach(filteredResults) { item in
                                            SongRowLikeView(
                                                title: item.title,
                                                artistName: {
                                                    switch item {
                                                        
                                                    case .song:
                                                        return "\(item.artistName)"
                                                        
                                                    case .album:
                                                        return "\(item.artistName)"
                                                        
                                                    case .artist:
                                                        return "Artist"
                                                    }
                                                }(),
                                                artworkURL: item.artworkURL,
                                                isArtist: {
                                                    if case .artist = item {
                                                        return true
                                                    }
                                                    return false
                                                }(),
                                                currentlyPlayingSong: $playerManager.currentlyPlayingSong
                                            )
                                            .id(item.id)
                                            .onTapGesture {
                                                UIApplication.shared.sendAction(
                                                    #selector(UIResponder.resignFirstResponder),
                                                    to: nil,
                                                    from: nil,
                                                    for: nil
                                                )
                                                
                                                switch item {
                                                    
                                                case .song(let song):
                                                    
                                                    Analytics.logEvent("search_result_song_tapped", parameters: [
                                                        "song_id": song.id.rawValue,
                                                        "title": song.title,
                                                        "artist": song.artistName,
                                                        "query": searchQuery
                                                    ])
                                                    
                                                    let songsFromSearch = filteredResults.compactMap { r -> Song? in
                                                        if case .song(let s) = r {
                                                            return s
                                                        }
                                                        return nil
                                                    }
                                                    
                                                    playerManager.playbackSource = .search
                                                    
                                                    playerManager.playSong(
                                                        song,
                                                        from: songsFromSearch
                                                    )
                                                    
                                                    playerManager.isPlayingFromAlbum = false
                                                    
                                                    let baseSize: CGFloat = 60
                                                    let scale = UIScreen.main.scale
                                                    let pixelSize = Int(baseSize * scale * 2)
                                                    
                                                    addRecentSearch(.song(
                                                        id: song.id,
                                                        title: song.title,
                                                        artist: song.artistName,
                                                        artworkURL: song.artwork?.url(width: pixelSize, height: pixelSize)
                                                    ))
                                                    
                                                case .album(let album):
                                                    
                                                    Analytics.logEvent("search_result_album_tapped", parameters: [
                                                        "album_id": album.id.rawValue,
                                                        "title": album.title,
                                                        "artist": album.artistName,
                                                        "query": searchQuery
                                                    ])
                                                    
                                                    let baseSize: CGFloat = 60
                                                    let scale = UIScreen.main.scale
                                                    let pixelSize = Int(baseSize * scale * 2)
                                                    
                                                    addRecentSearch(.album(
                                                        id: album.id,
                                                        title: album.title,
                                                        artist: album.artistName,
                                                        artworkURL: album.artwork?.url(width: pixelSize, height: pixelSize)
                                                    ))
                                                    
                                                    navigationPath.append(.album(album.id))
                                                    
                                                case .artist(let artist):
                                                    
                                                    Analytics.logEvent("search_result_artist_tapped", parameters: [
                                                        "artist_id": artist.id.rawValue,
                                                        "artist_name": artist.name,
                                                        "query": searchQuery
                                                    ])
                                                    
                                                    let baseSize: CGFloat = 60
                                                    let scale = UIScreen.main.scale
                                                    let pixelSize = Int(baseSize * scale * 2)
                                                    
                                                    addRecentSearch(.artist(
                                                        id: artist.id,
                                                        name: artist.name,
                                                        artworkURL: artist.artwork?.url(width: pixelSize, height: pixelSize)
                                                    ))
                                                    
                                                    navigationPath.append(.artist(artist.id))
                                                }
                                            }
                                            .padding(.vertical, 4)
                                            .background(Color(.systemBackground))
                                        }
                                    }
                                    .padding(.bottom,
                                             playerManager.currentlyPlayingSong != nil &&
                                             !keyboardObserver.isKeyboardVisible
                                             ? bottomPlayerHeight
                                             : 0
                                    )
                                }
                                .onChange(of: selectedTab) {
                                    guard let first = filteredResults.first else { return }
                                    withAnimation {
                                        proxy.scrollTo(first.id, anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchQuery, prompt: "Search Christian music")
                    .focused($isSearchFocused)
                    .onSubmit(of: .search) {
                        Task { await performSearch() }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            
            .onAppear {
                loadRecentSearches()
                Analytics.logEvent("search_viewed", parameters: nil)
            }
            
            .onChange(of: isSearchFocused) { oldValue, newValue in
                if newValue == false {
                    searchResults = []
                    isSearching = false
                }
            }
            
            .onChange(of: searchQuery) { oldValue, newValue in
                if newValue.isEmpty {
                    searchResults = []
                    isSearching = false
                }
            }
            
            .navigationDestination(for: Route.self) { route in
                switch route {
                    
                case .album(let albumID):
                    if let album = albumCache[albumID] {
                        AlbumDetailView(
                            album: album,
                            playSong: { song in
                                let songsFromResults = searchResults.compactMap { item -> Song? in
                                    if case .song(let s) = item { return s }
                                    return nil
                                }
                                
                                playerManager.playbackSource = .album
                                
                                playerManager.playSong(
                                    song,
                                    from: songsFromResults,
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
                        // Fetch album if not in cache
                        AlbumDetailLoadingView(
                            albumID: albumID,
                            playerManager: playerManager,
                            networkMonitor: networkMonitor,
                            navigationPath: $navigationPath,
                            albumCache: $albumCache
                        )
                    }
                    
                case .fullAlbumGrid:
                    EmptyView() // not used here
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
                            playerManager.playbackSource = isFromArtist ? .artist : .search
                            
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
                case .artistAlbumGrid(let title, let albums):
                    FullAlbumGridView(
                        albums: albums,
                        title: title,
                        cacheAlbum: { album in
                            albumCache[album.id] = album
                        },
                        isFromArtist: true,
                        navigationPath: $navigationPath,
                        networkMonitor: networkMonitor,
                        playerManager: playerManager
                    )
                case .recentlyPlayedGrid:
                    EmptyView() // Not used here
                }
            }
        }
    }
    
    
    private func loadRecentSearches() {
        guard let decoded = try? JSONDecoder().decode([RecentSearchItem].self, from: recentSearchData) else {
            recentSearches = []
            return
        }
        recentSearches = decoded
    }
    
    private func addRecentSearch(_ item: RecentSearchItem) {
        recentSearches.removeAll { $0.id == item.id }
        recentSearches.insert(item, at: 0)
        
        if recentSearches.count > 20 {
            recentSearches = Array(recentSearches.prefix(20))
        }
        
        if let encoded = try? JSONEncoder().encode(recentSearches) {
            recentSearchData = encoded
        }
    }
    
    // MARK: - Filtered Results
    private var filteredResults: [SearchResultItem] {
        guard networkMonitor.isConnected else { return [] }
        
        switch selectedTab {
            
        case .all:
            return searchResults
            
        case .songs:
            return searchResults.compactMap {
                if case .song(let s) = $0 {
                    return .song(s)
                }
                return nil
            }
            
        case .albums:
            return searchResults.compactMap {
                if case .album(let a) = $0 {
                    return .album(a)
                }
                return nil
            }
            
        case .artists:
            return searchResults.compactMap {
                if case .artist(let a) = $0 {
                    return .artist(a)
                }
                return nil
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
    
    // MARK: - Perform Search
    private func performSearch() async {
        
        guard !searchQuery.isEmpty else { return }
        guard networkMonitor.isConnected else { return }
        
        isSearching = true
        searchResults = []
        
        defer { isSearching = false }
        
        do {
            
            var request = MusicCatalogSearchRequest(
                term: searchQuery,
                types: [Song.self, Album.self, Artist.self]
            )
            
            request.limit = 25
            
            let response = try await request.response()
            
            var results: [SearchResultItem] = []
            
            // MARK: - Songs
            
            let christianSongs = response.songs.filter {
                
                ($0.genreNames.contains("Christian") ||
                 $0.genreNames.contains("Christian & Gospel")) &&
                $0.contentRating != .explicit
            }
            
            results.append(contentsOf: christianSongs.map {
                .song($0)
            })
            
            // MARK: - Albums
            
            let christianAlbums = response.albums.filter { album in
                
                (album.genreNames.contains("Christian") ||
                 album.genreNames.contains("Christian & Gospel")) &&
                album.contentRating != .explicit
            }
            
            results.append(contentsOf: christianAlbums.map {
                .album($0)
            })
            
            // MARK: - Artists
            
            var validArtists: [Artist] = []
            
            for artist in response.artists {
                
                do {
                    
                    var artistRequest = MusicCatalogResourceRequest<Artist>(
                        matching: \.id,
                        equalTo: artist.id
                    )
                    
                    artistRequest.properties = [
                        .albums,
                        .topSongs
                    ]
                    
                    artistRequest.limit = 1
                    
                    let artistResponse = try await artistRequest.response()
                    
                    guard let fullArtist = artistResponse.items.first else {
                        continue
                    }
                    
                    let hasChristianAlbum =
                    fullArtist.albums?.contains(where: {
                        $0.genreNames.contains("Christian") ||
                        $0.genreNames.contains("Christian & Gospel") &&
                        $0.contentRating != .explicit
                    }) ?? false
                    
                    let hasChristianSong =
                    fullArtist.topSongs?.contains(where: {
                        $0.genreNames.contains("Christian") ||
                        $0.genreNames.contains("Christian & Gospel") &&
                        $0.contentRating != .explicit
                    }) ?? false
                    
                    if hasChristianAlbum || hasChristianSong {
                        validArtists.append(fullArtist)
                    }
                    
                } catch {
                    print("Error loading artist: \(error)")
                }
            }
            
            results.append(contentsOf: validArtists.map {
                .artist($0)
            })
            
            searchResults = results
            
            for album in christianAlbums {
                albumCache[album.id] = album
            }
            
            Analytics.logEvent("search_performed", parameters: [
                "query": searchQuery,
                "result_count": results.count
            ])
            
            if results.isEmpty {
                
                Analytics.logEvent("search_no_results", parameters: [
                    "query": searchQuery
                ])
            }
            
        } catch {
            
            print("Error searching MusicKit: \(error)")
            searchResults = []
        }
    }
    
    private func handleRecentSearchTap(_ item: RecentSearchItem) {
        switch item {

        case .song(let id, let title, let artist, _):

            Analytics.logEvent("recent_search_tapped_song", parameters: [
                "song_id": id.rawValue,
                "title": title,
                "artist": artist
            ])

            Task {
                do {
                    let request = MusicCatalogResourceRequest<Song>(
                        matching: \.id,
                        equalTo: id
                    )

                    let response = try await request.response()

                    guard let song = response.items.first else { return }

                    await MainActor.run {
                        playerManager.playbackSource = .search

                        playerManager.playSong(
                            song,
                            from: []
                        )
                    }

                } catch {
                    print("Failed to load song from recent search: \(error)")
                }
            }

        case .album(let id, let title, let artist, _):

            Analytics.logEvent("recent_search_tapped_album", parameters: [
                "album_id": id.rawValue,
                "title": title,
                "artist": artist
            ])

            navigationPath.append(.album(MusicItemID(id.rawValue)))

        case .artist(let id, let name, _):

            Analytics.logEvent("recent_search_tapped_artist", parameters: [
                "artist_id": id.rawValue,
                "name": name
            ])

            navigationPath.append(.artist(MusicItemID(id.rawValue)))
        }
    }
    
    private var recentSearchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Text("Recent Searches")
                        .font(.headline)

                    Spacer()

                    if !recentSearches.isEmpty {
                        Button("Clear") {
                            showClearRecentAlert = true
                        }
                        .font(.footnote)
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)

                if recentSearches.isEmpty {
                    Text("No recent searches")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentSearches) { item in
                            SongRowLikeView(
                                title: {
                                    switch item {
                                    case .song(_, let title, _, _): return title
                                    case .album(_, let title, _, _): return title
                                    case .artist(_, let name, _): return name
                                    }
                                }(),
                                artistName: {
                                    switch item {
                                    case .song(_, _, let artist, _):
                                        return "Song | \(artist)"
                                    case .album(_, _, let artist, _):
                                        return "Album | \(artist)"
                                    case .artist:
                                        return "Artist"
                                    }
                                }(),
                                artworkURL: {
                                    switch item {
                                    case .song(_, _, _, let url),
                                         .album(_, _, _, let url),
                                         .artist(_, _, let url):
                                        return url
                                    }
                                }(),
                                isArtist: {
                                    if case .artist = item { return true }
                                    return false
                                }(),
                                currentlyPlayingSong: $playerManager.currentlyPlayingSong
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleRecentSearchTap(item)
                            }
                        }
                    }
                }

                Spacer(minLength: 80)
            }
        }
        .alert("Clear recent searches?", isPresented: $showClearRecentAlert) {
            Button("Clear", role: .destructive) {
                recentSearches = []
                recentSearchData = Data()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct SongRowLikeView: View {
    let title: String
    let artistName: String
    let artworkURL: URL?
    
    let isArtist: Bool
    
    @Binding var currentlyPlayingSong: Song?
    
    var body: some View {
        HStack(spacing: 8) {

            let screenWidth = UIScreen.main.bounds.width
            let artworkSize = min(max(screenWidth * 0.15, 50), 100)

            // If you control URL creation upstream, prefer passing a pre-sized URL.
            let highResURL = artworkURL

            CustomAsyncImage(url: highResURL, isCircle: isArtist)
                .frame(width: artworkSize, height: artworkSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }
}

