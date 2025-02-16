//
//  ContentView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 1/31/25.
//

import SwiftUI
import MusicKit
import AVFoundation

// MARK: - Main ContentView

struct ContentView: View {
    // Existing song/player state
    @State private var musicAuthorized = false
    @State private var songs: [Song] = []
    @State private var currentlyPlayingSong: Song?
    @State private var showSignInAlert = false
    @State private var appleMusicSubscription = false
    @State private var audioPlayer: AVPlayer?
    @State private var userAuthorized = false
    @State private var isPlaying = false
    @State private var subscriptionMessage: String? = nil  // Inline message for non-subscribed users
    @State private var showTrackDetail: Bool = false
    
    // New album-related state
    @State private var albums: [Album] = []
    @State private var selectedAlbum: Album? = nil
    @State private var showAlbumDetail = false
    @State private var isPlayingFromAlbum: Bool = false // Track if playing from album
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Main Content
                ScrollView {
                    VStack {
                        if musicAuthorized {
                            // MARK: Albums Section
                            if !albums.isEmpty {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text("Top Albums")
                                            .font(.title2)
                                            .bold()
                                        Spacer()
                                        if albums.count > 5 {
                                            NavigationLink("View More") {
                                                FullAlbumGridView(albums: albums) { album in
                                                    selectedAlbum = album
                                                    showAlbumDetail = true
                                                }
                                            }
                                            .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 16) {
                                            ForEach(albums.prefix(5), id: \.id) { album in
                                                AlbumCarouselItemView(album: album)
                                                    .onTapGesture {
                                                        selectAlbum(album)
                                                    }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // MARK: Tracks Section
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Top Songs")
                                        .font(.title2)
                                        .bold()
                                    Spacer()
                                    if songs.count > 5 {
                                        NavigationLink("View More") {
                                            FullTrackListView(songs: songs, playSong: playSong, currentlyPlayingSong: $currentlyPlayingSong, isPlayingFromAlbum: $isPlayingFromAlbum)
                                        }
                                        .foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 5)
                                
                                // Show only 5 songs initially
                                ForEach(songs.prefix(5), id: \.id) { song in
                                    SongRowView(song: song, playSong: playSong, currentlyPlayingSong: $currentlyPlayingSong, isPlayingFromAlbum: $isPlayingFromAlbum)
                                }
                            }
                        } else {
                            Text("Requesting Apple Music access...")
                        }
                    }
                    .padding(.horizontal, 16) // Add horizontal padding to the ScrollView
                    .padding(.bottom, 80) // Add padding to avoid overlap with BottomPlayerView
                }
                
                // MARK: Bottom Player View and Subscription Message
                if let song = currentlyPlayingSong {
                    VStack(spacing: 0) {
                        // Subscription Message (above BottomPlayerView)
                        if let message = subscriptionMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .padding(.bottom, 4) // Add some padding below the message
                                .background(Color(.systemBackground)) // Ensure the background covers the message
                        }
                        
                        // Bottom Player View
                        BottomPlayerView(song: song, isPlaying: $isPlaying, togglePlayPause: togglePlayPause)
                            .onTapGesture {
                                if isPlayingFromAlbum {
                                    showAlbumDetail = true
                                } else {
                                    showTrackDetail = true
                                }
                            }
                    }
                    .background(Color(.systemBackground)) // Ensure the background covers the BottomPlayerView and message
                }
            }
            .sheet(item: $selectedAlbum) { album in
                            NavigationStack {
                                AlbumDetailView(album: album, playSong: playSong, isPlayingFromAlbum: $isPlayingFromAlbum)
                                    .onAppear {
                                        print("Showing details for album: \(album.title)")
                                    }
                            }
                        }
            .sheet(isPresented: $showTrackDetail) {
                if let song = currentlyPlayingSong {
                    TrackDetailView(song: song, isPlaying: $isPlaying, togglePlayPause: togglePlayPause, subscriptionMessage: $subscriptionMessage)
                }
            }
            .task {
                await requestMusicAuthorization()
                if musicAuthorized {
                    await fetchChristianSongs()
                    await fetchChristianAlbums()
                    await checkAppleMusicStatus()
                }
            }
        }
    }
    
    // MARK: - Authorization & Fetching
    
    func requestMusicAuthorization() async {
        let status = await MusicAuthorization.request()
        if status == .authorized {
            musicAuthorized = true
            userAuthorized = true
            await checkAppleMusicStatus()
        } else {
            musicAuthorized = false
            userAuthorized = false
        }
    }
    
    func checkAppleMusicStatus() async {
        do {
            let subscription = try await MusicSubscription.current
            appleMusicSubscription = subscription.canPlayCatalogContent
        } catch {
            print("Error checking Apple Music subscription: \(error)")
            appleMusicSubscription = false
            showSignInAlert = true
        }
    }
    
    func fetchChristianGenre() async throws -> Genre? {
        // Hardcoded genre ID for "Christian & Gospel"
        let christianGenreID = MusicItemID("22") // Replace with the correct genre ID
        
        // Create a request to fetch the genre by its ID
        var request = MusicCatalogResourceRequest<Genre>(matching: \.id, equalTo: christianGenreID)
        request.limit = 1 // Fetch only one result
        
        // Execute the request
        let response = try await request.response()
        
        // Return the first matching genre
        return response.items.first
    }
    
    func fetchChristianSongs() async {
        do {
            // Fetch the "Christian & Gospel" genre
            guard let christianGenre = try await fetchChristianGenre() else {
                print("Christian & Gospel genre not found")
                return
            }
            
            // Create a request for top Christian songs
            var request = MusicCatalogChartsRequest(genre: christianGenre, types: [Song.self])
            request.limit = 50
            
            // Execute the request
            let response = try await request.response()
            
            // Extract songs from each chart
            let songCharts: [MusicCatalogChart<Song>] = response.songCharts
            
            // Flatten the array to get a list of songs
            songs = songCharts.flatMap { $0.items }
            
            
        } catch {
            print("Error fetching Christian songs: \(error)")
        }
    }
    
    
    func fetchChristianAlbums() async {
        do {
            // Fetch the "Christian & Gospel" genre
            guard let christianGenre = try await fetchChristianGenre() else {
                print("Christian & Gospel genre not found")
                return
            }
            
            // Create a charts request for albums in the Christian & Gospel genre
            var request = MusicCatalogChartsRequest(genre: christianGenre, types: [Album.self])
            request.limit = 50  // Get up to 50 albums
            
            // Execute the request
            let response = try await request.response()
            
            // Extract the album charts
            let albumCharts: [MusicCatalogChart<Album>] = response.albumCharts
            
            // Extract albums from the charts
            albums = albumCharts.flatMap { $0.items }
            
        } catch {
            print("Error fetching top Christian albums: \(error)")
        }
    }
    
    // MARK: - Playback
    
    func playSong(_ song: Song) {
        Task {
            await checkAppleMusicStatus()
            if appleMusicSubscription {
                do {
                    let player = ApplicationMusicPlayer.shared
                    player.queue = [song]
                    try await player.play()
                    currentlyPlayingSong = song
                    isPlaying = true
                    subscriptionMessage = nil
                } catch {
                    print("Error playing full song: \(error.localizedDescription)")
                    showSignInAlert = true
                }
            } else if let previewURL = song.previewAssets?.first?.url {
                // Prevent overlapping previews.
                audioPlayer?.pause()
                if let currentItem = audioPlayer?.currentItem {
                    NotificationCenter.default.removeObserver(self,
                                                              name: .AVPlayerItemDidPlayToEndTime,
                                                              object: currentItem)
                }
                // Create a new AVPlayer for the preview.
                audioPlayer = AVPlayer(url: previewURL)
                if let playerItem = audioPlayer?.currentItem {
                    NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                           object: playerItem,
                                                           queue: .main) { _ in
                        self.isPlaying = false
                        self.subscriptionMessage = "Preview ended. Log in or subscribe to Apple Music to play the full song."
                    }
                }
                audioPlayer?.play()
                currentlyPlayingSong = song
                isPlaying = true
                subscriptionMessage = nil
            } else {
                print("No preview available and user is not subscribed.")
            }
        }
    }
    
    // MARK: - Settings & Toggle
    
    func togglePlayPause() {
        if appleMusicSubscription {
            let player = ApplicationMusicPlayer.shared
            if isPlaying {
                player.pause()
            } else {
                Task {
                    do {
                        try await player.play()
                    } catch {
                        print("Error resuming playback: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            if isPlaying {
                audioPlayer?.pause()
            } else {
                audioPlayer?.play()
            }
        }
        isPlaying.toggle()
    }
    
    private func selectAlbum(_ album: Album) {
            if selectedAlbum?.id == album.id {
                // Same album selected, showing detail view
                selectedAlbum = album // Ensure the sheet is presented
                return
            }
        
            selectedAlbum = album
        }
}
// MARK: - Full Track List View

struct FullTrackListView: View {
    let songs: [Song]
    let playSong: (Song) -> Void
    @Binding var currentlyPlayingSong: Song?
    @Binding var isPlayingFromAlbum: Bool
    
    @State private var searchQuery: String = "" // State for search query
    @FocusState private var isSearchBarFocused: Bool // Track search bar focus state
    
    // Filtered songs based on search query (title or artist name)
    var filteredSongs: [Song] {
        if searchQuery.isEmpty {
            return songs // Return all songs if search query is empty
        } else {
            return songs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchQuery) ||
                song.artistName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    var body: some View {
        VStack {
            // Search Bar with Clear Button
            HStack {
                TextField("Search tracks...", text: $searchQuery)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .focused($isSearchBarFocused) // Track focus state
                    .onSubmit {
                        // Dismiss keyboard when user presses return
                        isSearchBarFocused = false
                    }
                
                // Clear Search Button
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = "" // Clear the search query
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Track List or Empty State
            if filteredSongs.isEmpty {
                // Empty State Message
                Text("No tracks found")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, 50)
            } else {
                List {
                    ForEach(filteredSongs, id: \.id) { song in
                        SongRowView(song: song, playSong: playSong, currentlyPlayingSong: $currentlyPlayingSong, isPlayingFromAlbum: $isPlayingFromAlbum)
                    }
                }
                .listStyle(.plain) // Use plain list style for better appearance
            }
        }
        .navigationTitle("Top Songs")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            // Dismiss keyboard when tapping outside the search bar
            isSearchBarFocused = false
        }
    }
}

// MARK: - Song Row View

struct SongRowView: View {
    let song: Song
    let playSong: (Song) -> Void
    @Binding var currentlyPlayingSong: Song?
    @Binding var isPlayingFromAlbum: Bool // Added binding
    
    var body: some View {
        HStack {
            if let artworkURL = song.artwork?.url(width: 100, height: 100) {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .empty:
                        Color.clear
                            .frame(width: 50, height: 50)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            VStack(alignment: .leading) {
                Text(song.title)
                    .font(.headline)
                Text(song.artistName)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .onTapGesture {
            playSong(song)
            isPlayingFromAlbum = false
        }
    }
}

struct TrackDetailView: View {
    let song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    @Binding var subscriptionMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            // Album Artwork
            if let artworkURL = song.artwork?.url(width: 250, height: 250) {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 250, height: 250)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .cornerRadius(12)
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Song Title (smaller font)
            Text(song.title)
                .font(.headline) // Smaller font size
                .multilineTextAlignment(.center)
                .lineLimit(2) // Allow up to 2 lines for longer titles

            // Artist Name
            Text(song.artistName)
                .font(.subheadline)
                .foregroundColor(.gray)

            // Play/Pause Button
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 48)) // Large play/pause button
                    .foregroundColor(.blue)
            }

            // Spacer to push content up
            Spacer()

            // Subscription Message (at the bottom, below the main content)
            if let message = subscriptionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8) // Add some padding below the message
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground)) // Ensure the background covers the message
            }
        }
        .padding()
        .frame(maxHeight: .infinity) // Ensure the VStack takes up the full height
    }
}

// MARK: - Bottom Player View

struct BottomPlayerView: View {
    let song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    
    var body: some View {
        HStack {
            if let artworkURL = song.artwork?.url(width: 50, height: 50) {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .cornerRadius(8)
                } placeholder: {
                    ProgressView()
                        .frame(width: 50, height: 50)
                }
            }
            VStack(alignment: .leading) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Full Album Grid View

struct FullAlbumGridView: View {
    let albums: [Album]
    let onAlbumSelected: (Album) -> Void
    
    @State private var searchQuery: String = "" // State for search query
    @FocusState private var isSearchBarFocused: Bool // Track search bar focus state
    
    // Filtered albums based on search query (title or artist name)
    var filteredAlbums: [Album] {
        if searchQuery.isEmpty {
            return albums // Return all albums if search query is empty
        } else {
            return albums.filter { album in
                album.title.localizedCaseInsensitiveContains(searchQuery) ||
                album.artistName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack {
            // Search Bar with Clear Button
            HStack {
                TextField("Search albums...", text: $searchQuery)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .focused($isSearchBarFocused) // Track focus state
                    .onSubmit {
                        // Dismiss keyboard when user presses return
                        isSearchBarFocused = false
                    }
                
                // Clear Search Button
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = "" // Clear the search query
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Album Grid or Empty State
            if filteredAlbums.isEmpty {
                // Empty State Message
                Text("No albums found")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, 50)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredAlbums, id: \.id) { album in
                            VStack {
                                if let artworkURL = album.artwork?.url(width: 150, height: 150) {
                                    AsyncImage(url: artworkURL) { phase in
                                        switch phase {
                                        case .empty:
                                            Color.gray.opacity(0.3)
                                                .frame(width: 150, height: 150)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 150, height: 150)
                                                .clipped()
                                                .cornerRadius(8)
                                        case .failure:
                                            Image(systemName: "photo")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 150, height: 150)
                                                .clipped()
                                                .foregroundColor(.gray)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                }
                                Text(album.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(album.artistName)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .onTapGesture {
                                onAlbumSelected(album)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Top Albums")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            // Dismiss keyboard when tapping outside the search bar
            isSearchBarFocused = false
        }
    }
}

// MARK: - Album Carousel Item View

struct AlbumCarouselItemView: View {
    let album: Album
    var body: some View {
        VStack {
            if let artworkURL = album.artwork?.url(width: 150, height: 150) {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .empty:
                        Color.gray.opacity(0.3)
                            .frame(width: 150, height: 150)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 150)
                            .clipped()
                            .cornerRadius(8)
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 150)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            Text(album.title)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(width: 150)
    }
}

// MARK: - Album Detail View

struct AlbumDetailView: View {
    let album: Album
    let playSong: (Song) -> Void
    
    @State private var tracks: [Song] = []
    @State private var isLoadingTracks: Bool = true
    @Binding var isPlayingFromAlbum: Bool // Added binding

   
    var body: some View {
        VStack {
            if let artworkURL = album.artwork?.url(width: 250, height: 250) {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .empty:
                        Color.clear
                            .frame(width: 250, height: 250)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .cornerRadius(12)
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            Text(album.title)
                .font(.headline) // Smaller font size
                .padding(.top)
            
            if isLoadingTracks {
                ProgressView("Loading tracks...")
                    .padding()
            } else if tracks.isEmpty {
                Text("No tracks available")
                    .padding()
            } else {
                List {
                    ForEach(tracks, id: \.id) { song in
                        Button {
                            playSong(song)
                            isPlayingFromAlbum = true
                        } label: {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .font(.headline)
                                Text(song.artistName)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchAlbumTracks()
        }
    }
    
    func fetchAlbumTracks() async {
        do {
            // Ensure tracks are explicitly requested
            var albumRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: album.id)
            albumRequest.properties = [.tracks] // Request track details
            
            let albumResponse = try await albumRequest.response()
            
            // Debug: Check if we received an album
            guard let albumWithTracks = albumResponse.items.first else {
                print("Error: Album not found.")
                tracks = []
                return
            }
            
            // Debug: Check if the album contains tracks
            guard let albumTracks = albumWithTracks.tracks, !albumTracks.isEmpty else {
                print("Error: Album has no tracks.")
                tracks = []
                return
            }
            
            // Extract track IDs
            let trackIDs = albumTracks.compactMap { $0.id }
            
            // Debug: Check if track IDs are available
            guard !trackIDs.isEmpty else {
                print("Error: No valid track IDs available.")
                return
            }
            
            // Fetch the actual song objects using track IDs
            let songsRequest = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: trackIDs)
            let songResponse = try await songsRequest.response()
            
            // Assign fetched songs to the tracks array
            tracks = Array(songResponse.items)
            
            
        } catch {
            print("Error fetching album tracks: \(error)")
            tracks = []
        }
        
        isLoadingTracks = false
    }
}


#Preview {
    ContentView()
}
