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
    @State private var playerIsReady = true
    @State private var userAuthorized = false
    @State private var isPlaying = false
    @State private var bottomMessage: String? = nil  // Inline message for non-subscribed users
    @State private var showTrackDetail: Bool = false
    @State private var previewDidEnd: Bool = false
    
    // New album-related state
    @State private var albums: [Album] = []
    @State private var albumWithTracks: AlbumWithTracks? = nil
    @State private var selectedAlbum: Album? = nil
    @State private var showAlbumDetail = false
    @State private var isPlayingFromAlbum: Bool = false // Track if playing from album
    
    @State private var isLoading = false // Track loading state
    @State private var hasRequestedMusicAuthorization = false
    
    @State private var isBottomPlayerVisible: Bool = true
    @State private var showBottomMessageOnce: Bool = true // Add this state variable
    @State private var bottomMessageShown: Int = 0
    
    @State private var playbackObservationTask: Task<Void, Never>?
    @State private var playerStateTask: Task<Void, Never>?
    @State private var playerPreparationTask: Task<Void, Never>? = nil
    
    @State private var navigationPath = NavigationPath()
    
    // Add scenePhase to detect app lifestyle changes
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                if isLoading || !hasRequestedMusicAuthorization {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                } else {
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
                                    .padding(.bottom, 16)
                                }
                                
                                // MARK: Tracks Section
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text("Top Christian Songs")
                                            .font(.system(size: 18))
                                            .bold()
                                        Spacer()
                                        if songs.count > 5 {
                                            NavigationLink("View More") {
                                                FullTrackListView(
                                                    songs: songs,
                                                    playSong: playSong,
                                                    currentlyPlayingSong: $currentlyPlayingSong,
                                                    isPlayingFromAlbum: $isPlayingFromAlbum,
                                                    bottomMessage: $bottomMessage
                                                )
                                            }
                                            .foregroundColor(.blue)
                                            .font(.system(size: 15))
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    
                                    ForEach(songs.prefix(5), id: \.id) { song in
                                        SongRowView(song: song, currentlyPlayingSong: $currentlyPlayingSong)
                                            .onTapGesture {
                                                playSong(song)
                                                isPlayingFromAlbum = false
                                                bottomMessage = nil
                                            }
                                    }
                                }
                            } else {
                                // Message for no music authorization
                                Text("Please allow Apple Music access to continue using this app.")
                                    .foregroundColor(.red)
                                    .padding()
                                
                                Button(action: {
                                    openAppSettings()
                                }) {
                                    Text("Enable in Settings")
                                        .foregroundColor(.blue)
                                }
                                .padding()
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    // Ensure ScrollView avoids the BottomPlayerView and bottomMessage
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 0) {
                            if let message = bottomMessage, showBottomMessageOnce {
                                HStack {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    
                                    Spacer()
                                    if bottomMessageShown >= 3 {
                                        Button("OK") {
                                            withAnimation {
                                                showBottomMessageOnce = false
                                            }
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemBackground))
                                .transition(.move(edge: .bottom).combined(with: .opacity)) // Smooth disappearing animation
                            }
                            
                            if let song = currentlyPlayingSong {
                                BottomPlayerView(
                                    song: song,
                                    isPlaying: $isPlaying,
                                    togglePlayPause: togglePlayPause,
                                    playerIsReady: playerIsReady
                                ).id(song.id)
                                    .background(Color(.systemBackground))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        showTrackDetail = true
                                    }
                            }
                        }
                    }
                    
                    .animation(.easeInOut(duration: 0.3), value: bottomMessage) // Animate the layout change
                    
                    
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
                AlbumDetailView(
                    album: album,
                    playSong: playSong,
                    isPlayingFromAlbum: $isPlayingFromAlbum,
                    bottomMessage: $bottomMessage,
                    albumWithTracks: $albumWithTracks
                )
            }
            .fullScreenCover(isPresented: $showTrackDetail) {
                if let song = currentlyPlayingSong {
                    TrackDetailView(
                        song: song,
                        isPlaying: $isPlaying,
                        togglePlayPause: togglePlayPause,
                        bottomMessage: $bottomMessage,
                        isPlayingFromAlbum: $isPlayingFromAlbum,
                        albumWithTracks: $albumWithTracks,
                        albums: albums,
                        playSong: playSong,
                        songs: $songs,
                        playerIsReady: $playerIsReady
                    )
                    .environment(\.navigationPath, $navigationPath)
                }
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    onAppForeground()
                }
            }
        }
    }
    
    
    func openAppSettings() {
        guard let appSettingsUrl = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(appSettingsUrl) else { return }
        
        UIApplication.shared.open(appSettingsUrl)
    }
    
    // Function to call when the app enters the foreground
    private func onAppForeground() {
        Task {
            await checkAppleMusicStatus() // Refresh subscription status
            refreshCurrentSong()
            if appleMusicSubscription {
                await stopAndReplaceAVPlayer()
                monitorMusicPlayerState()
            } else {
                await stopApplicationMusicPlayer()
            }
        }
    }
    
    private func refreshCurrentSong() {
        if appleMusicSubscription {
            if let item = ApplicationMusicPlayer.shared.queue.currentEntry?.item {
                switch item {
                case .song(let song):
                    currentlyPlayingSong = song
                default:
                    return
                }
            }
        }
    }
    
    func stopApplicationMusicPlayer() async {
        let player = ApplicationMusicPlayer.shared
        
        // Check if the playback status is playing or paused, and the queue is not empty
        if player.state.playbackStatus == .playing || player.state.playbackStatus == .paused {
            if !player.queue.entries.isEmpty {
                showTrackDetail = false // Dismiss TrackDetailView
                currentlyPlayingSong = nil
                clearApplicationMusicPlayer()
            }
        }
    }
    
    
    func stopAndReplaceAVPlayer() async {
        let player = ApplicationMusicPlayer.shared
        Task {
            await checkAppleMusicStatus() // Check if user is now logged in
            
            if appleMusicSubscription {
                // Stop the preview playback if it was playing
                audioPlayer?.pause()
                
                // Switch to ApplicationMusicPlayer for full playback
                if let currentSong = currentlyPlayingSong {
                    if player.state.playbackStatus != .playing || player.state.playbackStatus != .paused {
                        if player.queue.entries.isEmpty {
                            Task {
                                playSong(currentSong)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func monitorMusicPlayerState() {
        // Cancel the previous task if it exists
        playerStateTask?.cancel()
        
        // Start a new task
        playerStateTask = Task {
            let player = ApplicationMusicPlayer.shared
            while true {
                // Check for cancellation
                if Task.isCancelled {
                    print("Player state observation task cancelled.")
                    break
                }
                
                let state = player.state
                DispatchQueue.main.async {
                    self.isPlaying = (state.playbackStatus == .playing)
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            }
        }
    }
    
    
    // MARK: - Authorization & Fetching
    
    func requestMusicAuthorization() async {
        let status = await MusicAuthorization.request()
        if status == .authorized {
            musicAuthorized = true
            userAuthorized = true
            hasRequestedMusicAuthorization = true
        } else {
            musicAuthorized = false
            userAuthorized = false
            hasRequestedMusicAuthorization = true
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
                // Use ApplicationMusicPlayer for full playback
                
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
                
                bottomMessage = nil
                currentlyPlayingSong = song
                
                if !previewDidEnd {
                    playerPreparationTask?.cancel()
                    playerPreparationTask = nil
                    playerPreparationTask = Task {
                        await ensurePlayerPlays()
                    }
                    isPlaying = true
                } else {
                    playerPreparationTask?.cancel()
                    playerPreparationTask = nil
                    previewDidEnd = false
                    playerPreparationTask = Task {
                        await ensurePlayerIsReady()
                    }
                    isPlaying = true
                }
                
                observePlaybackState()
                
            } else if let previewURL = song.previewAssets?.first?.url {
                // Use AVPlayer for preview playback
                previewDidEnd = false
                audioPlayer?.pause()
                if let currentItem = audioPlayer?.currentItem {
                    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
                }
                
                audioPlayer = AVPlayer(url: previewURL)
                
                guard let audioPlayer = audioPlayer else {
                    print("Error: AVPlayer failed to initialize.")
                    return
                }
                
                if let playerItem = audioPlayer.currentItem {
                    NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
                        previewDidEnd(player: audioPlayer)
                        bottomMessageShown += 1
                        showSubscriptionMessage()
                    }
                }
                
                audioPlayer.play()
                currentlyPlayingSong = song
                isPlaying = true
                
                // Stop ApplicationMusicPlayer and clear its queue
                clearApplicationMusicPlayer()
                
            } else {
                print("No preview available and user is not subscribed.")
                // Clear ApplicationMusicPlayer queue and Command Center metadata
                clearApplicationMusicPlayer()
            }
        }
    }
    
    
    func ensurePlayerIsReady() async {
        let player = ApplicationMusicPlayer.shared
        
        await MainActor.run {
            self.playerIsReady = false
        }
        
        while true {
            // Exit loop if cancelled
            if Task.isCancelled {
                print("ensurePlayerIsReady was cancelled.")
                return
            }
            
            do {
                try await player.prepareToPlay()
            } catch {
                print("prepareToPlay failed: \(error.localizedDescription)")
            }
            
            if player.state.playbackStatus == .paused {
                await MainActor.run {
                    self.playerIsReady = true
                }
                print("✅ Player is ready: \(player.state.playbackStatus)")
                return
            }
            
            // Retry every 0.5s
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    func ensurePlayerPlays() async {
        let player = ApplicationMusicPlayer.shared
        
        await MainActor.run {
            self.playerIsReady = false
        }
        
        while true {
            // Exit loop if cancelled
            if Task.isCancelled {
                print("ensurePlayerIsReady was cancelled.")
                return
            }
            
            do {
                try await player.play()
            } catch {
                print("prepareToPlay failed: \(error.localizedDescription)")
            }
            
            if player.state.playbackStatus == .playing {
                await MainActor.run {
                    self.playerIsReady = true
                }
                print("✅ Player is ready: \(player.state.playbackStatus)")
                return
            }
            
            // Retry every 0.5s
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    
    
    
    func clearApplicationMusicPlayer() {
        if !appleMusicSubscription {
            let player = ApplicationMusicPlayer.shared
            do {
                // Stop playback
                player.stop()
                
                // Reset the queue to an empty state
                player.queue = .init()
                
                // Debug: Print the number of entries in the queue
                print("Queue entries after reset: \(player.queue.entries.count)")
                
                // Forcefully clear the queue if it's not empty
                if !player.queue.entries.isEmpty {
                    print("Forcing queue to clear...")
                    player.queue.entries.removeAll()
                }
                
                // Verify the queue is empty
                if player.queue.entries.isEmpty {
                    print("ApplicationMusicPlayer queue cleared successfully.")
                } else {
                    print("Warning: Queue still contains entries after reset.")
                }
                
                playbackObservationTask?.cancel()
                playbackObservationTask = nil
                
                playerStateTask?.cancel()
                playerStateTask = nil
            }
        }
    }
    
    func previewDidEnd(player: AVPlayer) {
        guard let currentSong = currentlyPlayingSong else { return }
        
        let nextSong: Song?
        
        previewDidEnd = true
        
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
        if !appleMusicSubscription {
            withAnimation {
                bottomMessage = "Preview ended. Log in or subscribe to Apple Music to play the full song."
            }
            if isPlayingFromAlbum {
                DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
                    withAnimation {
                        bottomMessage = nil
                    }
                }
            }
        } else {
            bottomMessage = nil
        }
    }
    
    // MARK: - Settings & Toggle
    
    // Updated togglePlayPause function
    func togglePlayPause() {
        
        if appleMusicSubscription {
            Task {
                do {
                    let player = ApplicationMusicPlayer.shared
                    
                    let state = player.state.playbackStatus
                    
                    if state == .playing {
                        player.pause()
                    } else {
                        try await player.play()
                    }
                    
                    // Force `isPlaying` update manually in case the observer is not fast enough
                    DispatchQueue.main.async {
                        self.isPlaying = (state == .paused)
                    }
                    
                } catch {
                    print("Error toggling playback: \(error.localizedDescription)")
                }
            }
            
        } else {
            if let audioPlayer = audioPlayer {
                if isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.play()
                    self.bottomMessage = nil
                }
            }
            
            isPlaying.toggle() // Only toggle manually for AVPlayer since we don't observe it
        }
    }
    
    private func selectAlbum(_ album: Album) {
        selectedAlbum = album
        navigationPath.append(album) // Simply append the album to the navigation path
    }
    
    private func observePlaybackState() {
        // Cancel the previous task if it exists
        playbackObservationTask?.cancel()
        
        // Start a new task
        playbackObservationTask = Task {
            let player = ApplicationMusicPlayer.shared
            var previousSong: Song? = currentlyPlayingSong
            
            while true {
                // Check for cancellation
                if Task.isCancelled {
                    print("Playback observation task cancelled.")
                    break
                }
                
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
                    print("No song playing")
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
    @Binding var bottomMessage: String?
    
    @State private var searchQuery: String = "" // State for search query
    
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
                                bottomMessage = nil
                            }
                            .padding(.vertical, 5)
                            .background(Color(.systemBackground))
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top) // Ensures the content stays at the top
        .navigationTitle("Top Songs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery) // Add the searchable modifier
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
            let screenWidth = UIScreen.main.bounds.width
            let songArtworkSize = min(max(screenWidth * 0.15, 50), 100) // Scales dynamically between 50-100pt
            
            if let artworkURL = song.artwork?.url(width: 150, height: 150) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: songArtworkSize, height: songArtworkSize)
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
    @Binding var bottomMessage: String?
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumWithTracks: AlbumWithTracks?
    let albums: [Album]
    let playSong: (Song) -> Void
    @Binding var songs: [Song]
    @Binding var playerIsReady: Bool
    
    @State private var selectedAlbum: Album? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigationPath) private var navigationPath
    
    @State private var animateTitle: Bool = false
    @State private var animateArtist: Bool = false
    
    private var appleMusicURL: URL? {
        URL(string: "https://music.apple.com/us/song/\(song.id)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    Spacer().frame(height: 60) // Adjust the space for the image and button
                    
                    // Album Artwork (Increased size)
                    if let artworkURL = song.artwork?.url(width: Int(geometry.size.width * 1.3), height: Int(geometry.size.width * 1.3)) {
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
                        
                        ZStack {
                            if playerIsReady {
                                Button(action: togglePlayPause) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.primary)
                                }
                            } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                        .frame(width: 60, height: 60) // Ensures fixed size
                        
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
                    if let appleMusicURL {
                        HStack {
                            Link(destination: appleMusicURL) {
                                Image("AppleMusicBadge")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: min(geometry.size.width * 0.09, 59))
                                    .padding(.top, 10)
                            }
                            .padding()
                        }
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
                    bottomMessage = nil
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
                    bottomMessage = nil
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
    let playerIsReady: Bool
    
    var body: some View {
        HStack {
            let screenWidth = UIScreen.main.bounds.width
            let songArtworkSize = min(max(screenWidth * 0.14, 40), 90) // Between 40-90pt
            
            // Song Artwork
            if let artworkURL = song.artwork?.url(width: 120, height: 120) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: songArtworkSize, height: songArtworkSize)
                    .clipped()
                    .cornerRadius(8)
            }
            
            // Song Title & Artist
            VStack(alignment: .leading) {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Play/Pause Button or Loading Indicator
            if playerIsReady {
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                .disabled(!playerIsReady)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 9)
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
    
    @State private var searchQuery: String = ""
    
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
    
    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let albumSize = max(min(screenWidth * 0.4, 255), 150) // Dynamic size: min 150px, max 255px
        
        let columns = [
            GridItem(.adaptive(minimum: albumSize), spacing: 20)
        ]
        
        VStack(alignment: .leading, spacing: 10) {
            if filteredAlbums.isEmpty {
                Spacer()
                Text("No albums found")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 30) { // Increased spacing
                        ForEach(filteredAlbums, id: \.id) { album in
                            VStack {
                                if let artworkURL = album.artwork?.url(width: 280, height: 280) {
                                    CustomAsyncImage(url: artworkURL)
                                        .frame(width: albumSize, height: albumSize)
                                        .clipped()
                                        .cornerRadius(12)
                                }
                                Text(album.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: albumSize - 20)
                                Text(album.artistName)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .frame(width: albumSize - 20)
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
        .searchable(text: $searchQuery)
    }
}

struct AlbumCarouselItemView: View {
    let album: Album
    
    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let albumSize = max(min(screenWidth * 0.4, 255), 150) // Dynamic size: min 150px, max 255px
        
        VStack {
            if let artworkURL = album.artwork?.url(width: 280, height: 280) {
                
                CustomAsyncImage(url: artworkURL)
                    .frame(width: albumSize, height: albumSize)
                    .clipped()
                    .cornerRadius(12)
            }
            
            Text(album.title)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 150) // Prevent text from stretching too wide
        }
        .frame(maxWidth: albumSize) // Ensure VStack wraps around the image properly
    }
}

// MARK: - Album Detail View

struct AlbumDetailView: View {
    let album: Album
    let playSong: (Song) -> Void
    
    @State private var tracks: [Song] = []
    @State private var isLoadingTracks: Bool = true
    @Binding var isPlayingFromAlbum: Bool // Added binding
    @Binding var bottomMessage: String?
    @Binding var albumWithTracks: AlbumWithTracks?
    
    
    
    var body: some View {
        VStack {
            if let artworkURL = album.artwork?.url(width: 350, height: 350) {
                let screenWidth = UIScreen.main.bounds.width
                let albumSize = min(max(screenWidth * 0.5, 150), 300) // Keeps size between 150-300pt
                
                CustomAsyncImage(url: artworkURL)
                    .frame(width: albumSize, height: albumSize)
                    .clipped()
                    .cornerRadius(12)
            }
            Text(album.title)
                .font(.headline)
                .padding(.top)
            Text(album.artistName)
                .font(.subheadline)
                .foregroundColor(.gray)
            
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
                            bottomMessage = nil
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
