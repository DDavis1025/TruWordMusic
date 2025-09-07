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
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor

    // Authorization & Data
    @State private var musicAuthorized = false
    @State private var hasRequestedMusicAuthorization = false
    @State private var isLoading = false

    // Songs & Albums
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var albumWithTracks: AlbumWithTracks? = nil

    // UI State
    @State private var navigationPath = NavigationPath()

    @Environment(\.scenePhase) private var scenePhase
    
    private let bottomPlayerHeight: CGFloat = 80

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !networkMonitor.isConnected && !isLoading {
                    noInternetView
                } else if isLoading || !hasRequestedMusicAuthorization {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                } else {
                    mainScrollView
                }
            }
            .navigationDestination(for: String.self) { value in
                if value == "fullAlbumGrid" {
                    FullAlbumGridView(
                        albums: albums,
                        onAlbumSelected: { album in navigationPath.append(album) },
                        networkMonitor: networkMonitor
                    )
                }
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(
                    album: album,
                    playSong: { song in
                        playerManager.playSong(
                            song,
                            from: songs,
                            albumWithTracks: albumWithTracks,
                            playFromAlbum: true,
                            networkMonitor: networkMonitor
                        )
                    },
                    isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                    bottomMessage: $playerManager.bottomMessage,
                    albumWithTracks: $albumWithTracks,
                    networkMonitor: networkMonitor
                )
            }
            .fullScreenCover(isPresented: $playerManager.showTrackDetail) {
                if let song = playerManager.currentlyPlayingSong {
                    TrackDetailView(
                        song: song,
                        isPlaying: $playerManager.isPlaying,
                        togglePlayPause: playerManager.togglePlayPause,
                        bottomMessage: $playerManager.bottomMessage,
                        isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                        albumWithTracks: $playerManager.albumWithTracks,
                        albums: albums,
                        playSong: { s in
                            playerManager.playSong(
                                s,
                                from: songs,
                                albumWithTracks: albumWithTracks,
                                playFromAlbum: false
                            )
                        },
                        songs: $songs,
                        playerIsReady: $playerManager.playerIsReady,
                        networkMonitor: networkMonitor,
                        appleMusicSubscription: $playerManager.appleMusicSubscription
                    )
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await checkAppleMusicStatus() }
                }
            }
        }
    }


    
    // MARK: - UI
    
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
            Color.clear.frame(height: bottomPlayerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private var mainScrollView: some View {
        ScrollView {
            VStack {
                if musicAuthorized {
                    albumsSection
                    songsSection
                } else {
                    Text("Please allow Apple Music access to continue using this app.")
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("Enable in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, bottomPlayerHeight + 16) // important!
        }
    }
    
    private var albumsSection: some View {
        if albums.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading) {
                HStack {
                    Text("Top Christian Albums")
                        .font(.system(size: 18)).bold()
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
                                .onTapGesture { navigationPath.append(album) }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
        )
    }
    
    private var songsSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Top Christian Songs")
                    .font(.system(size: 18)).bold()
                Spacer()
                if songs.count > 5 {
                    NavigationLink("View More") {
                        FullTrackListView(
                            songs: songs,
                            playSong: { song in
                                playerManager.playSong(song, from: songs, networkMonitor: networkMonitor)
                            },
                            currentPlayingSong: $playerManager.currentlyPlayingSong,
                            isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                            bottomMessage: $playerManager.bottomMessage,
                            networkMonitor: networkMonitor
                        )
                    }
                    .foregroundColor(.blue)
                    .font(.system(size: 15))
                }
            }
            .padding(.vertical, 5)
            
            ForEach(songs.prefix(5), id: \.id) { song in
                SongRowView(song: song, currentPlayingSong: $playerManager.currentlyPlayingSong)
                    .onTapGesture {
                        playerManager.playSong(song, from: songs)
                        playerManager.isPlayingFromAlbum = false
                        playerManager.bottomMessage = nil
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
        let christianGenreID = MusicItemID("22") // Christian & Gospel
        var request = MusicCatalogResourceRequest<Genre>(matching: \.id, equalTo: christianGenreID)
        request.limit = 1
        return try await request.response().items.first
    }
    
    private func fetchChristianSongs() async {
        do {
            guard let genre = try await fetchChristianGenre() else { return }
            var request = MusicCatalogChartsRequest(genre: genre, types: [Song.self])
            request.limit = 50
            songs = (try await request.response()).songCharts.flatMap { $0.items }
        } catch { print("Error fetching songs: \(error)") }
    }
    
    private func fetchChristianAlbums() async {
        do {
            guard let genre = try await fetchChristianGenre() else { return }
            var request = MusicCatalogChartsRequest(genre: genre, types: [Album.self])
            request.limit = 50
            albums = (try await request.response()).albumCharts.flatMap { $0.items }
        } catch { print("Error fetching albums: \(error)") }
    }
}


// MARK: - Full Track List View

struct FullTrackListView: View {
    let songs: [Song]
    let playSong: (Song) -> Void
    @Binding var currentPlayingSong: Song?
    @Binding var isPlayingFromAlbum: Bool
    @Binding var bottomMessage: String?
    
    @ObservedObject var networkMonitor: NetworkMonitor
    
    @State private var searchQuery: String = "" // State for search query
    
    private let bottomPlayerHeight: CGFloat = 80
    
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
            if !networkMonitor.isConnected {
                // No internet connection view
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
                    
                    // Add padding equal to the BottomPlayerView height
                    Color.clear
                        .frame(height: bottomPlayerHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if filteredSongs.isEmpty {
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
                                currentPlayingSong: $currentPlayingSong,
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
        .if(networkMonitor.isConnected) { view in
            view.searchable(text: $searchQuery)
        }
    }
}



// MARK: - Song Row View

struct SongRowView: View {
    let song: Song
    @Binding var currentPlayingSong: Song?
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
                    .foregroundColor(Color(white: 0.48))
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
    @ObservedObject var networkMonitor: NetworkMonitor
    @Binding var appleMusicSubscription: Bool
    
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
                        .foregroundColor(Color(white: 0.48))
                        .id("artist-\(song.id)") // Unique ID for the artist
                    
                    Spacer().frame(height: 30) // Ensures artist name is ~20 pts above play button
                    
                    // Controls (Previous, Play/Pause, Next)
                    HStack(spacing: 40) {
                        Button(action: playPreviousSong) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 28))
                                .foregroundColor(networkMonitor.isConnected ? .primary : .gray)
                        }
                        .disabled(!networkMonitor.isConnected)
                        
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
                                .foregroundColor(networkMonitor.isConnected ? .primary : .gray)
                        }
                        .disabled(!networkMonitor.isConnected)
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
                                .foregroundColor(networkMonitor.isConnected ? .blue : .gray)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .disabled(!networkMonitor.isConnected)
                        .padding(.top, 5)
                    }
                    
                    Spacer()
                    
                    // Subscription Message at the Bottom
                    if let appleMusicURL, !appleMusicSubscription {
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
        guard networkMonitor.isConnected else { return }
        animateTitle = false
        animateArtist = false
        
        if isPlayingFromAlbum,
           let albumWithTracks,
           let currentIndex = albumWithTracks.tracks.firstIndex(where: { $0.id == song.id }) {
            
            var previousIndex = currentIndex - 1
            while previousIndex >= 0 {
                let previousSong = albumWithTracks.tracks[previousIndex]
                let isPlayable = (previousSong.releaseDate.map { $0 <= Date() } ?? false) && previousSong.playParameters != nil
                if isPlayable {
                    playSong(previousSong)
                    return
                }
                previousIndex -= 1
            }
            
        } else if let currentIndex = songs.firstIndex(where: { $0.id == song.id }) {
            var previousIndex = currentIndex - 1
            while previousIndex >= 0 {
                let previousSong = songs[previousIndex]
                let isPlayable = (previousSong.releaseDate.map { $0 <= Date() } ?? false) && previousSong.playParameters != nil
                if isPlayable {
                    playSong(previousSong)
                    bottomMessage = nil
                    return
                }
                previousIndex -= 1
            }
        }
    }
    
    
    private func playNextSong() {
        guard networkMonitor.isConnected else { return }
        animateTitle = false
        animateArtist = false
        
        if isPlayingFromAlbum,
           let albumWithTracks,
           let currentIndex = albumWithTracks.tracks.firstIndex(where: { $0.id == song.id }) {
            
            var nextIndex = currentIndex + 1
            while nextIndex < albumWithTracks.tracks.count {
                let nextSong = albumWithTracks.tracks[nextIndex]
                let isPlayable = (song.releaseDate.map { $0 <= Date() } ?? false) && nextSong.playParameters != nil
                if isPlayable {
                    playSong(nextSong)
                    return
                }
                nextIndex += 1
            }
            
        } else if let currentIndex = songs.firstIndex(where: { $0.id == song.id }) {
            var nextIndex = currentIndex + 1
            while nextIndex < songs.count {
                let nextSong = songs[nextIndex]
                let isPlayable = (song.releaseDate.map { $0 <= Date() } ?? false) && nextSong.playParameters != nil
                if isPlayable {
                    playSong(nextSong)
                    bottomMessage = nil
                    return
                }
                nextIndex += 1
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
                    .foregroundColor(Color(white: 0.48))
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
    @ObservedObject var networkMonitor: NetworkMonitor
    
    @State private var searchQuery: String = ""
    
    private let bottomPlayerHeight: CGFloat = 80
    
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
            if !networkMonitor.isConnected {
                // No internet connection view
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
                    
                    // Add padding equal to the BottomPlayerView height
                    Color.clear
                        .frame(height: bottomPlayerHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if filteredAlbums.isEmpty {
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
                                    .foregroundColor(Color(white: 0.48))
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
        .if(networkMonitor.isConnected) { view in
            view.searchable(text: $searchQuery)
        }
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
    @ObservedObject var networkMonitor: NetworkMonitor
    
    var body: some View {
        VStack(spacing: 4) { // Controls vertical spacing
            if let artworkURL = album.artwork?.url(width: 350, height: 350) {
                let screenWidth = UIScreen.main.bounds.width
                let albumSize = min(max(screenWidth * 0.5, 150), 300)
                
                CustomAsyncImage(url: artworkURL)
                    .frame(width: albumSize, height: albumSize)
                    .clipped()
                    .cornerRadius(12)
            }
            
            Text(album.title)
                .font(.headline)
                .padding(.top, 2) // Slightly smaller than default padding
            
            Text(album.artistName)
                .font(.subheadline)
                .foregroundColor(Color(white: 0.48)) // white: 0.0 = black, 1.0 = white
            
            if let releaseDate = album.releaseDate {
                Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundColor(Color(white: 0.48))
                    .padding(.bottom, 2)
            }
            
            if isLoadingTracks {
                ProgressView("Loading tracks...")
                    .padding()
            } else if tracks.isEmpty {
                Text("No tracks available")
                    .padding()
            } else {
                List {
                    ForEach(tracks, id: \.id) { song in
                        let isPlayable = (song.releaseDate.map { $0 <= Date() } ?? false) && song.playParameters != nil
                        
                        Button {
                            if isPlayable {
                                // Only update if it's a different album
                                if albumWithTracks?.album.id != album.id {
                                    albumWithTracks = AlbumWithTracks(album: album, tracks: tracks)
                                }
                                playSong(song)
                                isPlayingFromAlbum = true
                                bottomMessage = nil
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundColor(isPlayable && networkMonitor.isConnected ? .primary : Color(UIColor.lightGray))
                                Text(song.artistName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(isPlayable && networkMonitor.isConnected ? Color(white: 0.48) : Color(UIColor.lightGray))
                            }
                            .padding(.vertical, 3)
                        }
                        .disabled(!isPlayable || !networkMonitor.isConnected)
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
            
        } catch {
            print("Error fetching album tracks: \(error)")
            tracks = []
        }
        
        isLoadingTracks = false
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

