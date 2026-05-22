import SwiftUI
import MusicKit
import FirebaseAnalytics

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
        switch self {
        case .song(let song):
            return song.artwork?.url(width: 150, height: 150)
            
        case .album(let album):
            return album.artwork?.url(width: 150, height: 150)
            
        case .artist(let artist):
            return artist.artwork?.url(width: 150, height: 150)
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
    
    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResultItem] = []
    @State private var isSearching: Bool = false
    @State private var selectedTab: SearchTab = .all
    
    @Binding var albumCache: [MusicItemID: Album]
    
    let albums: [Album]
    
    
    @Namespace private var tabNamespace
    private let bottomPlayerHeight: CGFloat = 77
    
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
                        HStack(spacing: 0) {
                            ForEach(SearchTab.allCases) { tab in
                                Button {
                                    withAnimation(.spring()) {
                                        selectedTab = tab
                                    }
                                    
                                    // 🔥 Track tab change
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
                        
                        // MARK: - Content
                        if isSearching {
                            ProgressView("Searching…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.bottom,
                                         playerManager.currentlyPlayingSong != nil && !keyboardObserver.isKeyboardVisible
                                         ? bottomPlayerHeight
                                         : 0
                                )
                            
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
                                                    
                                                case .album(let album):
                                                    
                                                    Analytics.logEvent("search_result_album_tapped", parameters: [
                                                        "album_id": album.id.rawValue,
                                                        "title": album.title,
                                                        "artist": album.artistName,
                                                        "query": searchQuery
                                                    ])
                                                    
                                                    navigationPath.append(.album(album.id))
                                                    
                                                case .artist(let artist):
                                                    
                                                    Analytics.logEvent("search_result_artist_tapped", parameters: [
                                                        "artist_id": artist.id.rawValue,
                                                        "artist_name": artist.name,
                                                        "query": searchQuery
                                                    ])
                                                    
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
                    .onSubmit(of: .search) {
                        Task { await performSearch() }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            
            // 🔥 Track screen view
            .onAppear {
                Analytics.logEvent("search_viewed", parameters: nil)
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
                            playerManager: playerManager
                        )
                        .id(album.id)
                    } else {
                        VStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
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
                }
            }
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
}

// MARK: - Row View (Shared by Songs & Albums)
struct SongRowLikeView: View {
    let title: String
    let artistName: String
    let artworkURL: URL?
    
    let isArtist: Bool
    
    @Binding var currentlyPlayingSong: Song?
    
    var body: some View {
        HStack(spacing: 8) {
            if let url = artworkURL {
                CustomAsyncImage(url: url, isCircle: isArtist)
                    .frame(width: 60, height: 60)
            }
            
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

