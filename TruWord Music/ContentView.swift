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

struct AlbumWithTracks {
    var album: Album
    var tracks: [Song]
}

// Define a custom environment key
struct NavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath>? = nil
}

// Extend EnvironmentValues to include the custom key
extension EnvironmentValues {
    var navigationPath: Binding<NavigationPath>? {
        get { self[NavigationPathKey.self] }
        set { self[NavigationPathKey.self] = newValue }
    }
}


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
    @State private var albumsWithTracks: [AlbumWithTracks] = []
    @State private var selectedAlbum: Album? = nil
    @State private var showAlbumDetail = false
    @State private var isPlayingFromAlbum: Bool = false // Track if playing from album
    
    // Custom array to track albums in the navigation stack
    @State private var albumsInNavigationPath: [Album] = []
    
    
    @State private var navigationPath = NavigationPath()
    
    // Add scenePhase to detect app lifestyle changes
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                                                    selectAlbum(album)
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
                            .id(song.id) // Force re-render when song changes
                            .onTapGesture {
                                showTrackDetail = true
                            }
                    }
                    .background(Color(.systemBackground)) // Ensure the background covers the BottomPlayerView and message
                }
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album, playSong: playSong, albumsWithTracks: albumsWithTracks, isPlayingFromAlbum: $isPlayingFromAlbum)
                    .onAppear {
                        print("Showing details for album: \(album.title)")
                    }
            }
            .sheet(isPresented: $showTrackDetail) {
                if let song = currentlyPlayingSong {
                    TrackDetailView(
                        song: song,
                        isPlaying: $isPlaying,
                        togglePlayPause: togglePlayPause,
                        subscriptionMessage: $subscriptionMessage,
                        isPlayingFromAlbum: $isPlayingFromAlbum,
                        albumsWithTracks: $albumsWithTracks,
                        albums: albums,
                        playSong: playSong, // Pass the playSong function
                        songs: $songs // Pass the songs array as a binding
                    )
                    .environment(\.navigationPath, $navigationPath)
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    // App has entered the foreground
                    onAppForeground()
                }
            }
        }
    }
    
    // Function to call when the app enters the foreground
    private func onAppForeground() {
        refreshCurrentSong()
    }
    
    private func refreshCurrentSong() {
        if appleMusicSubscription {
            if let item = ApplicationMusicPlayer.shared.queue.currentEntry?.item {
                switch item {
                case .song(let song):
                    currentlyPlayingSong = song
                default:
                    currentlyPlayingSong = nil // Handle other cases if needed
                }
            } else {
                currentlyPlayingSong = nil
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
           
            // Iterate through each album and fetch its tracks
            for album in albums {
                let tracks = await fetchTracksForAlbum(album: album)
                let albumWithTracks = AlbumWithTracks(album: album, tracks: tracks)
                albumsWithTracks.append(albumWithTracks)
            }
            
        } catch {
            print("Error fetching top Christian albums: \(error)")
        }
    }
    
    
    func fetchTracksForAlbum(album: Album) async -> [Song] {
        do {
            // Ensure tracks are explicitly requested
            var albumRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: album.id)
            albumRequest.properties = [.tracks] // Request track details
            
            let albumResponse = try await albumRequest.response()
            
            // Check if we received an album
            guard let albumWithTracks = albumResponse.items.first else {
                print("Error: Album not found.")
                return []
            }
            
            // Check if the album contains tracks
            guard let albumTracks = albumWithTracks.tracks, !albumTracks.isEmpty else {
                print("Error: Album has no tracks.")
                return []
            }
            
            // Extract track IDs
            let trackIDs = albumTracks.compactMap { $0.id }
            
            // Check if track IDs are available
            guard !trackIDs.isEmpty else {
                print("Error: No valid track IDs available.")
                return []
            }
            
            // Fetch the actual song objects using track IDs
            let songsRequest = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: trackIDs)
            let songResponse = try await songsRequest.response()
            
            // Return fetched songs
            return Array(songResponse.items)
            
        } catch {
            print("Error fetching album tracks: \(error)")
            return []
        }
    }
    
    // MARK: - Playback
    
    func playSong(_ song: Song) {
        Task {
            await checkAppleMusicStatus()
            if appleMusicSubscription {
                do {
                    let player = ApplicationMusicPlayer.shared
                    let queueSongs: [Song]
                  
                    // Check if the song is from an album
                    if let albumWithTracks = albumsWithTracks.first(where: { $0.tracks.contains(song) }), isPlayingFromAlbum {
                        queueSongs = albumWithTracks.tracks
                    } else {
                        queueSongs = songs
                    }
                    
                    // Ensure the queue is set correctly
                    guard let startIndex = queueSongs.firstIndex(of: song) else {
                        print("Error: Song not found in queue list.")
                        return
                    }
                    
                    // Set the queue with the selected song first, then the rest of the queue
                    let orderedQueue = Array(queueSongs[startIndex...]) + Array(queueSongs[..<startIndex])
                    player.queue = ApplicationMusicPlayer.Queue(for: orderedQueue)
                    
                    // Start playback immediately
                    try await player.play()
                    
                    currentlyPlayingSong = song
                    isPlaying = true
                    subscriptionMessage = nil
                    
                    // Start observing playback state
                    observePlaybackState()
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
                if audioPlayer == nil {
                        print("Error: AVPlayer failed to initialize.")
                    }
                if let playerItem = audioPlayer?.currentItem {
                    NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                         object: playerItem,
                                                         queue: .main) { _ in
                        if let audioPlayer = audioPlayer {
                            previewDidEnd(player: audioPlayer)
                        }
                        showSubscriptionMessage()
                    }
                }
                audioPlayer?.play()
                currentlyPlayingSong = song
                isPlaying = true
            } else {
                print("No preview available and user is not subscribed.")
            }
        }
    }
    
    func previewDidEnd(player: AVPlayer) {
        guard let currentSong = currentlyPlayingSong else { return }
        
        let nextSong: Song?
        
        if isPlayingFromAlbum, let albumWithTracks = albumsWithTracks.first(where: { $0.tracks.contains(currentSong) }) {
            // Playing from an album, get the next track
            if let currentIndex = albumWithTracks.tracks.firstIndex(of: currentSong), currentIndex < albumWithTracks.tracks.count - 1 {
                nextSong = albumWithTracks.tracks[currentIndex + 1]
            } else {
                nextSong = nil // No more tracks in the album
            }
        } else {
            nextSong = nil // No more songs in the list
            let timeZero = CMTime(seconds: 0, preferredTimescale: 1)
            player.seek(to: timeZero) { finished in
                if finished {
                    print("Seek to 0 completed")
                }
            }
        }
        
        if let nextSongToPlay = nextSong {
            playSong(nextSongToPlay)
        } else {
            isPlaying = false
            let timeZero = CMTime(seconds: 0, preferredTimescale: 1)
            player.seek(to: timeZero) { finished in
                if finished {
                    print("Seek to 0 completed")
                }
            }
        }
    }
    
    func showSubscriptionMessage() {
        withAnimation {
            subscriptionMessage = "Preview ended. Log in or subscribe to Apple Music to play the full song."
        }
        if isPlayingFromAlbum {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                withAnimation {
                    subscriptionMessage = nil
                }
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
                // If the preview has ended and the user presses play, restart the preview
                audioPlayer?.play()
                self.subscriptionMessage = nil
            }
        }
        isPlaying.toggle()
    }
    
    private func selectAlbum(_ album: Album) {
        selectedAlbum = album
        
        // Check if the album is already in the navigation path
        if albumsInNavigationPath.contains(where: { $0.id == album.id }) {
            // If the album is already in the path, remove it and re-append it
            if !navigationPath.isEmpty {
                navigationPath.removeLast()
            }
            if !albumsInNavigationPath.isEmpty {
                albumsInNavigationPath.removeLast()
            }
        }
        
        // Append the album to the navigation path and the custom array
        navigationPath.append(album)
        albumsInNavigationPath.append(album)
    }
    
    private func observePlaybackState() {
        Task {
            let player = ApplicationMusicPlayer.shared
            var previousSong: Song? = currentlyPlayingSong
            
            while true {
                // Check the current song every second
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                if let currentEntry = player.queue.currentEntry {
                    switch currentEntry.item {
                    case .song(let song):
                        // Extract the song from the current entry
                        if isPlayingFromAlbum {
                            // Find the song in the album's track list
                            if let albumWithTracks = albumsWithTracks.first(where: { $0.tracks.contains(where: { $0.id == song.id }) }),
                               let currentSong = albumWithTracks.tracks.first(where: { $0.id == song.id }) {
                                if currentSong != previousSong {
                                    // Song has changed
                                    previousSong = currentSong
                                    currentlyPlayingSong = currentSong
                                    isPlaying = true
                                }
                            }
                        } else {
                            // Find the song in the general songs list
                            if let currentSong = songs.first(where: { $0.id == song.id }) {
                                if currentSong != previousSong {
                                    // Song has changed
                                    previousSong = currentSong
                                    currentlyPlayingSong = currentSong
                                    isPlaying = true
                                }
                            }
                        }
                    default:
                        // Handle other cases (e.g., album, playlist)
                        break
                    }
                } else {
                    // No song is playing
                    isPlaying = false
                }
            }
        }
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
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumsWithTracks: [AlbumWithTracks]
    let albums: [Album]
    let playSong: (Song) -> Void
    @Binding var songs: [Song] // Add this line
    
    
    @State private var selectedAlbum: Album? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigationPath) private var navigationPath // Access the navigation path
    
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
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // Artist Name
            Text(song.artistName)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Play/Pause Button with Previous and Next Buttons
            HStack {
                // Previous Button
                Button(action: {
                    playPreviousSong()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                
                // Play/Pause Button
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                }
                
                // Next Button
                Button(action: {
                    playNextSong()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
            }
            
            // View Album Button (only show if playing from an album)
            if isPlayingFromAlbum {
                Button(action: {
                    // Find the selected album
                    selectedAlbum = albumsWithTracks.first(where: { albumWithTracks in
                        albumWithTracks.tracks.contains(where: { $0.id == song.id })
                    })?.album
                    
                    // Dismiss the sheet
                    dismiss()
                    
                    // Push the selected album onto the navigation stack
                    if let selectedAlbum = selectedAlbum {
                        navigationPath?.wrappedValue.append(selectedAlbum)
                    }
                }) {
                    Text("View Album")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // Spacer to push content up
            Spacer()
            
            // Subscription Message
            if let message = subscriptionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
    
    // Function to play the previous song
    private func playPreviousSong() {
        if isPlayingFromAlbum {
            // Logic to play the previous song in the album
            if let album = albumsWithTracks.first(where: { $0.tracks.contains(where: { $0.id == song.id }) }) {
                if let currentIndex = album.tracks.firstIndex(where: { $0.id == song.id }) {
                    let previousIndex = currentIndex - 1
                    if previousIndex >= 0 {
                        let previousSong = album.tracks[previousIndex]
                        playSong(previousSong)
                    }
                }
            }
        } else {
            // Logic to play the previous song in the general song list
            if let currentIndex = songs.firstIndex(where: { $0.id == song.id }) {
                let previousIndex = currentIndex - 1
                if previousIndex >= 0 {
                    let previousSong = songs[previousIndex]
                    playSong(previousSong)
                    if !isPlayingFromAlbum {
                        subscriptionMessage = nil
                    }
                }
            }
        }
    }
    
    // Function to play the next song
    private func playNextSong() {
        if isPlayingFromAlbum {
            // Logic to play the next song in the album
            if let album = albumsWithTracks.first(where: { $0.tracks.contains(where: { $0.id == song.id }) }) {
                if let currentIndex = album.tracks.firstIndex(where: { $0.id == song.id }) {
                    let nextIndex = currentIndex + 1
                    if nextIndex < album.tracks.count {
                        let nextSong = album.tracks[nextIndex]
                        playSong(nextSong)
                    }
                }
            }
        } else {
            // Logic to play the next song in the general song list
            if let currentIndex = songs.firstIndex(where: { $0.id == song.id }) {
                let nextIndex = currentIndex + 1
                if nextIndex < songs.count {
                    let nextSong = songs[nextIndex]
                    playSong(nextSong)
                    if !isPlayingFromAlbum {
                        subscriptionMessage = nil
                    }
                }
            }
        }
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
                CustomAsyncImage(
                    url: artworkURL,
                    placeholder: Image(systemName: "music.note") // Fallback placeholder
                )
                .frame(width: 50, height: 50)
                .cornerRadius(8)
            } else {
                Image(systemName: "music.note") // Fallback icon if artwork is nil
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
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
    let albumsWithTracks: [AlbumWithTracks] // Add this parameter
    
    @Binding var isPlayingFromAlbum: Bool
    
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
                .font(.headline)
                .padding(.top)
            
            // Find the tracks for the selected album
            if let albumWithTracks = albumsWithTracks.first(where: { $0.album.id == album.id }) {
                List {
                    ForEach(albumWithTracks.tracks, id: \.id) { song in
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
            } else {
                Text("No tracks available")
                    .padding()
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
    }
}


#Preview {
    ContentView()
}
