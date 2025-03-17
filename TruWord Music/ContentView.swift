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
    @State private var appleMusicSubscription = false
    @State private var audioPlayer: AVPlayer?
    @State private var userAuthorized = false
    @State private var isPlaying = false
    @State private var subscriptionMessage: String? = nil  // Inline message for non-subscribed users
    @State private var showTrackDetail: Bool = false
    
    // New album-related state
    @State private var albums: [Album] = []
    @State private var albumWithTracks: AlbumWithTracks? = nil
    @State private var selectedAlbum: Album? = nil
    @State private var showAlbumDetail = false
    @State private var isPlayingFromAlbum: Bool = false // Track if playing from album
    
    @State private var isLoading = false // Track loading state
    
    @State private var navigationPath = NavigationPath()
    
    // Add scenePhase to detect app lifestyle changes
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                if isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                } else {
                    // Main Content
                    ScrollView {
                        VStack {
                            if musicAuthorized {
                                // MARK: Albums Section
                                if !albums.isEmpty {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text("Top Christian Albums")
                                                .font(.system(size: 18))
                                                .bold()
                                            Spacer()
                                            if albums.count > 5 {
                                                NavigationLink("View More", value: "fullAlbumGrid")
                                                    .foregroundColor(.blue)
                                                    .font(.system(size: 15))
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
                                    .padding(.bottom, 16) // Add padding to the bottom of the first VStack
                                }
                                
                                // MARK: Tracks Section
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text("Top Christian Songs")
                                            .font(.system(size: 18)) // Smaller than .title2 (22pt)
                                            .bold()
                                        Spacer()
                                        if songs.count > 5 {
                                            NavigationLink("View More") {
                                                FullTrackListView(songs: songs, playSong: playSong, currentlyPlayingSong: $currentlyPlayingSong, isPlayingFromAlbum: $isPlayingFromAlbum, subscriptionMessage: $subscriptionMessage)
                                            }
                                            .foregroundColor(.blue)
                                            .font(.system(size: 15)) // Smaller than .title2 (22pt)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    
                                    // Show only 5 songs initially
                                    ForEach(songs.prefix(5), id: \.id) { song in
                                        SongRowView(song: song, currentlyPlayingSong: $currentlyPlayingSong)
                                            .onTapGesture {
                                                playSong(song)
                                                isPlayingFromAlbum = false
                                                subscriptionMessage = nil
                                            }
                                    }
                                }
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
            }
            .navigationDestination(for: String.self) { value in
                if value == "fullAlbumGrid" {
                    FullAlbumGridView(albums: albums) { album in
                        selectAlbum(album)
                    }
                }
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album, playSong: playSong, isPlayingFromAlbum: $isPlayingFromAlbum, subscriptionMessage: $subscriptionMessage, albumWithTracks: $albumWithTracks)
                    .onAppear {
                        print("Showing details for album: \(album.title)")
                    }
            }
            .fullScreenCover(isPresented: $showTrackDetail) {
                if let song = currentlyPlayingSong {
                    TrackDetailView(
                        song: song,
                        isPlaying: $isPlaying,
                        togglePlayPause: togglePlayPause,
                        subscriptionMessage: $subscriptionMessage,
                        isPlayingFromAlbum: $isPlayingFromAlbum,
                        albumWithTracks: $albumWithTracks,
                        albums: albums,
                        playSong: playSong,
                        songs: $songs
                    )
                    .environment(\.navigationPath, $navigationPath)

              }
            }
            .task {
                isLoading = true
                await requestMusicAuthorization()

                if musicAuthorized {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await fetchChristianSongs() }
                        group.addTask { await fetchChristianAlbums() }
                    }
                }
                
                isLoading = false
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
                    let queueSongs: [Song]
                    
                    if let albumWithTracks, albumWithTracks.tracks.contains(song), isPlayingFromAlbum {
                        queueSongs = albumWithTracks.tracks
                    } else {
                        queueSongs = songs
                    }
                    
                    guard let startIndex = queueSongs.firstIndex(of: song) else {
                        print("Error: Song not found in queue list.")
                        return
                    }
                    
                    let orderedQueue = Array(queueSongs[startIndex...]) + Array(queueSongs[..<startIndex])
                    player.queue = ApplicationMusicPlayer.Queue(for: orderedQueue)
                    
                    try await player.play()
                    
                    currentlyPlayingSong = song
                    isPlaying = true
                    subscriptionMessage = nil
                    
                    observePlaybackState()
                } catch {
                    print("Error playing full song: \(error.localizedDescription)")
                }
            } else if let previewURL = song.previewAssets?.first?.url {
                // Ensure no overlapping previews
                audioPlayer?.pause()
                if let currentItem = audioPlayer?.currentItem {
                    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
                }
                
                // Initialize AVPlayer safely
                audioPlayer = AVPlayer(url: previewURL)
                
                guard let audioPlayer = audioPlayer else {
                    print("Error: AVPlayer failed to initialize.")
                    return
                }
                
                if let playerItem = audioPlayer.currentItem {
                    NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
                        previewDidEnd(player: audioPlayer)
                        showSubscriptionMessage()
                    }
                }
                
                audioPlayer.play()
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
        
        if isPlayingFromAlbum, let albumWithTracks, albumWithTracks.tracks.contains(currentSong) {
            // Find the current song's index in the album's track list
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
        print("album \(album)")
        navigationPath.append(album) // Simply append the album to the navigation path
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
                        if isPlayingFromAlbum,
                           let albumWithTracks, // Unwrap optional AlbumWithTracks
                           let currentSong = albumWithTracks.tracks.first(where: { $0.id == song.id }) {
                            
                            if currentSong != previousSong {
                                // Song has changed
                                previousSong = currentSong
                                currentlyPlayingSong = currentSong
                                isPlaying = true
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
    @Binding var subscriptionMessage: String?
    
    @State private var searchQuery: String = "" // State for search query
    @FocusState private var isSearchBarFocused: Bool // Track search bar focus state
    
    // Filtered songs based on search query (title or artist name)
    var filteredSongs: [Song] {
        if searchQuery.isEmpty {
            return songs
        } else {
            return songs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchQuery) ||
                song.artistName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Search Bar at the Top
            HStack {
                TextField("Search tracks...", text: $searchQuery)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .focused($isSearchBarFocused)
                    .onSubmit { isSearchBarFocused = false }
                
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Content Section (List or Empty State)
            if filteredSongs.isEmpty {
                Spacer()
                Text("No tracks found")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredSongs, id: \.id) { song in
                            SongRowView(
                                song: song,
                                currentlyPlayingSong: $currentlyPlayingSong,
                                leftPadding: 8,
                                rightPadding: 8
                            )
                            .onTapGesture {
                                playSong(song)
                                isPlayingFromAlbum = false
                                subscriptionMessage = nil
                            }
                            .padding(.vertical, 5)
                            .background(Color(.systemBackground))
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top) // Ensures the search bar stays at the top
        .navigationTitle("Top Songs")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture { isSearchBarFocused = false } // Dismiss keyboard on tap
    }
}



// MARK: - Song Row View

struct SongRowView: View {
    let song: Song
    @Binding var currentlyPlayingSong: Song?
    var leftPadding: CGFloat = 0 // Default left padding
    var rightPadding: CGFloat = 0 // Default right padding
    
    var body: some View {
        HStack {
            // Album Artwork with configurable left padding
            if let artworkURL = song.artwork?.url(width: 150, height: 150) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: 50, height: 50)
                    .clipped()
                    .cornerRadius(8)
                    .padding(.leading, leftPadding) // Use configurable left padding
            }
            
            // Song Title and Artist Name with configurable right padding
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                
                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .padding(.trailing, rightPadding) // Use configurable right padding
            
            Spacer()
            
        }
        .padding(.vertical, 5)
    }
}

struct TrackDetailView: View {
    let song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    @Binding var subscriptionMessage: String?
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumWithTracks: AlbumWithTracks?
    let albums: [Album]
    let playSong: (Song) -> Void
    @Binding var songs: [Song]
    
    @State private var selectedAlbum: Album? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigationPath) private var navigationPath
    
    @State private var animateTitle: Bool = false
    @State private var animateArtist: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    Spacer().frame(height: 60) // Adjust the space for the image and button
                    
                    // Album Artwork (Increased size)
                    if let artworkURL = song.artwork?.url(width: Int(geometry.size.width * 0.95), height: Int(geometry.size.width * 0.95)) {
                        CustomAsyncImage(url: artworkURL)
                            .frame(width: geometry.size.width * 0.85, height: geometry.size.width * 0.85)
                            .clipped()
                            .cornerRadius(8)
                            .id(song.id) // Unique ID to force recreation when song changes
                    }
                    
                    Spacer().frame(height: 14) // More space between image and title
                    
                    // Song Title
                    ScrollableText(text: song.title, isAnimating: $animateTitle, scrollSpeed: 47.0)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .id("title-\(song.id)") // Unique ID for the title
                    
                    Spacer().frame(height: 12) // More space between title and artist name
                    
                    // Artist Name
                    ScrollableText(text: song.artistName, isAnimating: $animateArtist, scrollSpeed: 47.0)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .id("artist-\(song.id)") // Unique ID for the artist
                    
                    Spacer().frame(height: 30) // Ensures artist name is ~20 pts above play button
                    
                    // Controls (Previous, Play/Pause, Next)
                    HStack(spacing: 40) {
                        Button(action: playPreviousSong) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: playNextSong) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.bottom, 10)
                    
                    // View Album Button
                    if isPlayingFromAlbum {
                        Button(action: {
                            if let albumWithTracks, albumWithTracks.tracks.contains(where: { $0.id == song.id }) {
                                selectedAlbum = albumWithTracks.album
                            }
                            
                            dismiss()
                            
                            if let selectedAlbum = selectedAlbum {
                                navigationPath?.wrappedValue.append(selectedAlbum)
                            }
                        }) {
                            Text("View Album")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .padding(.top, 5)
                    }
                    
                    Spacer()
                    
                    // Subscription Message at the Bottom
                    if let message = subscriptionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemBackground))
                    }
                }
                
                // Close Button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.primary)
                                .padding()
                        }
                    }
                    Spacer()
                }
            }
            .padding(.horizontal)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    private func playPreviousSong() {
        // Reset the animation state
        animateTitle = false
        animateArtist = false
        
        if isPlayingFromAlbum,
           let albumWithTracks, // Unwrap single album
           let currentIndex = albumWithTracks.tracks.firstIndex(where: { $0.id == song.id }) {
            
            let previousIndex = currentIndex - 1
            if previousIndex >= 0 {
                let previousSong = albumWithTracks.tracks[previousIndex]
                playSong(previousSong)
            }
        } else {
            if let currentIndex = songs.firstIndex(where: { $0.id == song.id }) {
                let previousIndex = currentIndex - 1
                if previousIndex >= 0 {
                    let previousSong = songs[previousIndex]
                    playSong(previousSong)
                    subscriptionMessage = nil
                }
            }
        }
    }
    
    private func playNextSong() {
        // Reset the animation state
        animateTitle = false
        animateArtist = false
        
        if isPlayingFromAlbum {
            if isPlayingFromAlbum,
               let albumWithTracks,
               let currentIndex = albumWithTracks.tracks.firstIndex(where: { $0.id == song.id }) {
                
                let nextIndex = currentIndex + 1
                if nextIndex < albumWithTracks.tracks.count {
                    let nextSong = albumWithTracks.tracks[nextIndex]
                    playSong(nextSong)
                }
            }
        } else {
            if let currentIndex = songs.firstIndex(where: { $0.id == song.id }) {
                let nextIndex = currentIndex + 1
                if nextIndex < songs.count {
                    let nextSong = songs[nextIndex]
                    playSong(nextSong)
                    subscriptionMessage = nil
                }
            }
        }
    }
}


struct ScrollableText: View {
    let text: String
    @Binding var isAnimating: Bool
    let scrollSpeed: CGFloat
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var phase: AnimationPhase = .idle
    
    enum AnimationPhase {
        case idle
        case scrollingLeft
        case paused
        case scrollingRight
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Measure text width
                Text(text)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(GeometryReader { textGeometry in
                        Color.clear
                            .onAppear {
                                updateWidths(textGeometry: textGeometry, containerWidth: geometry.size.width)
                            }
                            .onChange(of: text) {
                                updateWidths(textGeometry: textGeometry, containerWidth: geometry.size.width)
                            }
                    })
                    .hidden() // Hide measuring text
                
                // Visible scrolling text
                Text(text)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: calculateOffset())
                    .animation(.linear(duration: calculateDuration()), value: phase) // Use calculated duration
                    .onChange(of: phase) { _, _ in handleAnimationState() }
            }
        }
        .frame(height: 25) // Constrain height to avoid excessive spacing
        .clipped()
        .onTapGesture {
            if textWidth > containerWidth && !isAnimating {
                isAnimating = true
                phase = .scrollingLeft
            }
        }
    }
    
    private func updateWidths(textGeometry: GeometryProxy, containerWidth: CGFloat) {
        textWidth = textGeometry.size.width
        self.containerWidth = containerWidth
    }
    
    private func calculateOffset() -> CGFloat {
        switch phase {
        case .idle:
            return 0
        case .scrollingLeft:
            return -textWidth + containerWidth
        case .paused:
            return -textWidth + containerWidth
        case .scrollingRight:
            return 0
        }
    }
    
    private func calculateDuration() -> Double {
        let distance = textWidth - containerWidth
        return Double(distance / scrollSpeed)
    }
    
    private func handleAnimationState() {
        switch phase {
        case .scrollingLeft:
            DispatchQueue.main.asyncAfter(deadline: .now() + calculateDuration()) { phase = .paused }
        case .paused:
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { phase = .scrollingRight }
        case .scrollingRight:
            DispatchQueue.main.asyncAfter(deadline: .now() + calculateDuration()) {
                phase = .idle
                isAnimating = false
            }
        case .idle:
            break
        }
    }
    
    // Method to reset the phase
    func resetPhase() {
        phase = .idle
    }
}

// MARK: - Bottom Player View

struct BottomPlayerView: View {
    let song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    
    var body: some View {
        HStack {
            if let artworkURL = song.artwork?.url(width: 150, height: 150) {
                CustomAsyncImage(
                    url: artworkURL
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

struct FullAlbumGridView: View {
    let albums: [Album]
    let onAlbumSelected: (Album) -> Void
    
    @State private var searchQuery: String = "" // State for search query
    @FocusState private var isSearchBarFocused: Bool // Track search bar focus state
    
    // Filtered albums based on search query (title or artist name)
    var filteredAlbums: [Album] {
        if searchQuery.isEmpty {
            return albums
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
        VStack(alignment: .leading, spacing: 10) {
            // Search Bar at the Top
            HStack {
                TextField("Search albums...", text: $searchQuery)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .focused($isSearchBarFocused)
                    .onSubmit { isSearchBarFocused = false }

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Content Section (Grid or Empty State)
            if filteredAlbums.isEmpty {
                // Keeps the message below the search bar
                Spacer()
                Text("No albums found")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredAlbums, id: \.id) { album in
                            VStack {
                                if let artworkURL = album.artwork?.url(width: 200, height: 200) {
                                    CustomAsyncImage(url: artworkURL)
                                        .frame(width: 150, height: 150)
                                        .clipped()
                                        .cornerRadius(8)
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
        .frame(maxHeight: .infinity, alignment: .top) // Ensures the search bar stays at the top
        .navigationTitle("Top Albums")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture { isSearchBarFocused = false } // Dismiss keyboard on tap
    }
}


// MARK: - Album Carousel Item View

struct AlbumCarouselItemView: View {
    let album: Album
    var body: some View {
        VStack {
            if let artworkURL = album.artwork?.url(width: 250, height: 250) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: 150, height: 150)
                    .clipped()
                    .cornerRadius(8)
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
    @Binding var subscriptionMessage: String?
    @Binding var albumWithTracks: AlbumWithTracks?
    
    
    
    var body: some View {
        VStack {
            if let artworkURL = album.artwork?.url(width: 350, height: 350) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: 250, height: 250)
                    .clipped()
                    .cornerRadius(8)
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
                            subscriptionMessage = nil
                        } label: {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(song.artistName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 3) // Increase vertical padding
                        }
                    }
                }
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchAlbumTracks(album: album)
        }
    }
    
    func fetchAlbumTracks(album: Album) async {
        do {
            // Ensure tracks are explicitly requested
            var albumRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: album.id)
            albumRequest.properties = [.tracks] // Request track details
            
            let albumResponse = try await albumRequest.response()
            
            // Debug: Check if we received an album
            guard let fetchedAlbum = albumResponse.items.first else {
                print("Error: Album not found.")
                tracks = []
                return
            }
            
            // Debug: Check if the album contains tracks
            guard let albumTracks = fetchedAlbum.tracks, !albumTracks.isEmpty else {
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
            
            albumWithTracks = AlbumWithTracks(album: album, tracks: tracks)
            
            
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
