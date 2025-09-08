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

// MARK: - Search View
struct SearchView: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor

    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResultItem] = []
    @State private var isSearching: Bool = false
    
    @Binding var navigationPath: NavigationPath // shared

    private let bottomPlayerHeight: CGFloat = 80

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(alignment: .leading, spacing: 10) {
                if !networkMonitor.isConnected {
                    noInternetView
                } else if isSearching {
                    ProgressView("Searching...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchQuery.isEmpty {
                    Spacer()
                    Text("No results found")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(searchResults) { item in
                                SongRowLikeView(
                                    title: item.title,
                                    artistName: item.artistName,
                                    artworkURL: item.artworkURL,
                                    currentlyPlayingSong: $playerManager.currentlyPlayingSong
                                )
                                .onTapGesture {
                                    switch item {
                                    case .song(let song):
                                        // Play song from search results
                                        let songsFromResults = searchResults.compactMap { result -> Song? in
                                            if case .song(let s) = result { return s } else { return nil }
                                        }
                                        playerManager.playSong(song, from: songsFromResults, playFromAlbum: false, networkMonitor: networkMonitor)
                                    case .album(let album):
                                        navigationPath.append(album)
                                    }
                                }
                                .padding(.vertical, 5)
                                .background(Color(.systemBackground))
                            }
                        }
                        .padding(.bottom, bottomPlayerHeight + 16)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Search Christian music")
            .onSubmit(of: .search) {
                Task { await performSearch() }
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(
                    album: album,
                    playSong: { song in
                        // Build a flat array of songs from the search results
                        let songsFromResults = searchResults.compactMap { result -> Song? in
                            if case .song(let s) = result { return s } else { return nil }
                        }

                        // Play the selected song
                        playerManager.playSong(
                            song,
                            from: songsFromResults,
                            albumWithTracks: playerManager.albumWithTracks,
                            playFromAlbum: true, // user is navigating inside album
                            networkMonitor: networkMonitor
                        )
                    },
                    isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                    bottomMessage: $playerManager.bottomMessage,
                    albumWithTracks: $playerManager.albumWithTracks,
                    networkMonitor: networkMonitor
                )
            }
        }
    }

    
    // MARK: - Views
    
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
            Color.clear.frame(height: bottomPlayerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(searchResults) { item in
                    SongRowLikeView(
                        title: item.title,
                        artistName: item.artistName,
                        artworkURL: item.artworkURL,
                        currentlyPlayingSong: $playerManager.currentlyPlayingSong
                    )
                    .onTapGesture {
                        switch item {
                        case .song(let song):
                            // Pass the list of all songs in the search results
                            let songsFromSearch = searchResults.compactMap { result -> Song? in
                                if case .song(let s) = result { return s } else { return nil }
                            }
                            playerManager.playSong(song, from: songsFromSearch)
                            playerManager.isPlayingFromAlbum = false
                            playerManager.bottomMessage = nil
                        case .album(let album):
                            navigationPath.append(album) // Navigate to AlbumDetailView
                        }
                    }
                    .padding(.vertical, 5)
                    .background(Color(.systemBackground))
                }
            }
            .padding(.bottom, bottomPlayerHeight)
        }
    }
    
    
    // MARK: - Search
    
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
        HStack {
            let screenWidth = UIScreen.main.bounds.width
            let artworkSize = min(max(screenWidth * 0.15, 50), 100)
            
            if let url = artworkURL {
                CustomAsyncImage(url: url)
                    .frame(width: artworkSize, height: artworkSize)
                    .clipped()
                    .cornerRadius(8)
                    .padding(.leading, 8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(artistName)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.48))
                    .lineLimit(1)
            }
            .padding(.trailing, 8)
            
            Spacer()
        }
        .padding(.vertical, 5)
    }
}
