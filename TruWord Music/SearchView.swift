//
//  SearchView.swift
//  TruWordMusic
//
//  Created by Dillon Davis on 2025-09-07.
//

import SwiftUI
import MusicKit

// MARK: - Unified Result Model
enum SearchResultItem: Identifiable {
    case song(Song)
    case album(Album)
    
    var id: MusicItemID {
        switch self {
        case .song(let song): return song.id
        case .album(let album): return album.id
        }
    }
    
    var title: String {
        switch self {
        case .song(let song): return song.title
        case .album(let album): return album.title
        }
    }
    
    var artistName: String {
        switch self {
        case .song(let song): return song.artistName
        case .album(let album): return album.artistName
        }
    }
    
    var artworkURL: URL? {
        switch self {
        case .song(let song): return song.artwork?.url(width: 150, height: 150)
        case .album(let album): return album.artwork?.url(width: 150, height: 150)
        }
    }
}

// MARK: - Tab Selection Enum
enum SearchTab: String, CaseIterable, Identifiable {
    case all = "All"
    case songs = "Songs"
    case albums = "Albums"
    
    var id: String { rawValue }
}

struct SearchView: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var keyboardObserver = KeyboardObserver()
    @Binding var navigationPath: NavigationPath
    
    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResultItem] = []
    @State private var isSearching: Bool = false
    @State private var selectedTab: SearchTab = .all
    @State private var scrollOffsets: [SearchTab: CGFloat] = [:]
    
    @Namespace private var tabNamespace
    private let bottomPlayerHeight: CGFloat = 60
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            if !networkMonitor.isConnected {
                noInternetView
            } else {
                VStack(spacing: 0) {
                    // MARK: - Tab Bar
                    HStack(spacing: 0) {
                        ForEach(SearchTab.allCases) { tab in
                            Button {
                                withAnimation(.spring()) { selectedTab = tab }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                                    .foregroundColor(selectedTab == tab ? .accentColor : .gray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        ZStack {
                                            if selectedTab == tab {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.accentColor.opacity(0.2))
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
                    } else if filteredResults.isEmpty && !searchQuery.isEmpty {
                        Spacer()
                        Text("No results found")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
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
                                                            return "Song | \(item.artistName)"
                                                        case .album:
                                                            return "Album | \(item.artistName)"
                                                        }
                                                    }(),
                                            artworkURL: item.artworkURL,
                                            currentlyPlayingSong: $playerManager.currentlyPlayingSong
                                        )
                                        .id(item.id)
                                        .onTapGesture {
                                            // Dismiss keyboard
                                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                            switch item {
                                            case .song(let song):
                                                let songsFromSearch = filteredResults.compactMap { r -> Song? in
                                                    if case .song(let s) = r { return s } else { return nil }
                                                }
                                                playerManager.playSong(song, from: songsFromSearch)
                                                playerManager.isPlayingFromAlbum = false
                                            case .album(let album):
                                                DispatchQueue.main.async {
                                                    navigationPath.append(album)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 5)
                                        .background(Color(.systemBackground))
                                    }
                                }
                                .padding(.bottom, playerManager.currentlyPlayingSong != nil && !keyboardObserver.isKeyboardVisible ? bottomPlayerHeight : 0)
                            }
                            .onChange(of: selectedTab) {
                                if let firstItem = filteredResults.first {
                                    withAnimation {
                                        proxy.scrollTo(firstItem.id, anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationDestination(for: Album.self) { album in
                    AlbumDetailView(
                        album: album,
                        playSong: { song in
                            let songsFromResults = searchResults.compactMap { item -> Song? in
                                if case .song(let s) = item { return s } else { return nil }
                            }
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
                }
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchQuery, prompt: "Search Christian music")
                .onSubmit(of: .search) {
                    Task { await performSearch() }
                }
            }
        }
    }
    
    // MARK: - Filtered Results
        private var filteredResults: [SearchResultItem] {
            switch selectedTab {
            case .all: return searchResults
            case .songs: return searchResults.compactMap { if case .song(let s) = $0 { return .song(s) } else { return nil } }
            case .albums: return searchResults.compactMap { if case .album(let a) = $0 { return .album(a) } else { return nil } }
            }
        }
    
    // MARK: - Results List
    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredResults) { item in
                    SongRowLikeView(
                        title: item.title,
                        artistName: {
                                    switch item {
                                    case .song:
                                        return "Song | \(item.artistName)"
                                    case .album:
                                        return "Album | \(item.artistName)"
                                    }
                                }(),
                        artworkURL: item.artworkURL,
                        currentlyPlayingSong: $playerManager.currentlyPlayingSong
                    )
                    .onTapGesture {
                        switch item {
                        case .song(let song):
                            let songsFromSearch = filteredResults.compactMap { result -> Song? in
                                if case .song(let s) = result { return s } else { return nil }
                            }
                            playerManager.playSong(song, from: songsFromSearch)
                            playerManager.isPlayingFromAlbum = false
                        case .album(let album):
                            navigationPath.append(album)
                        }
                    }
                    .padding(.vertical, 5)
                    .background(Color(.systemBackground))
                }
            }
            .padding(.bottom, playerManager.currentlyPlayingSong != nil ? bottomPlayerHeight : 0)
        }
    }
    
    // MARK: - No Internet View
    private var noInternetView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No Internet connection")
                .font(.headline)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
            Text("Your device is not connected to the internet")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
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
    
    // MARK: - Perform Search
    private func performSearch() async {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        searchResults = []
        
        do {
            var request = MusicCatalogSearchRequest(term: searchQuery, types: [Song.self, Album.self])
            request.limit = 25
            let response = try await request.response()
            
            var results: [SearchResultItem] = []
            
            let christianSongs = response.songs.filter {
                $0.genreNames.contains("Christian") || $0.genreNames.contains("Christian & Gospel")
            }
            results.append(contentsOf: christianSongs.map { .song($0) })
            
            let christianAlbums = response.albums.filter {
                $0.genreNames.contains("Christian") || $0.genreNames.contains("Christian & Gospel")
            }
            results.append(contentsOf: christianAlbums.map { .album($0) })
            
            searchResults = results
        } catch {
            print("Error searching MusicKit: \(error)")
        }
        
        isSearching = false
    }
}

// MARK: - Row View (Shared by Songs & Albums)
struct SongRowLikeView: View {
    let title: String
    let artistName: String
    let artworkURL: URL?
    @Binding var currentlyPlayingSong: Song?

    var body: some View {
        HStack(spacing: 8) {
            if let url = artworkURL {
                CustomAsyncImage(url: url)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(artistName)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading) // Key: prevents row from expanding beyond screen
        .background(Color(.systemBackground))
    }
}


// MARK: - PreferenceKey for Scroll Offset
    struct ScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}


