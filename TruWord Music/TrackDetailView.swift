import SwiftUI
import MusicKit
import FirebaseAnalytics

struct TrackDetailView: View {
    @Binding var song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumWithTracks: AlbumWithTracks?
    @Binding var songs: [Song]
    @Binding var playerIsReady: Bool
    
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    @Binding var appleMusicSubscription: Bool
    @Binding var selectedAlbum: Album?
    
    @Binding var activeTab: AppTab
    @Binding var homeNavigationPath: [Route]
    @Binding var searchNavigationPath: [Route]
    @Binding var favoritesNavigationPath: [Route]
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favoritesManager: FavoritesManager
    
    @State private var animateTitle: Bool = false
    @State private var animateArtist: Bool = false
    
    @State private var albumStack: [Album] = []
    
    @State private var showActionsMenu = false
    @State private var menuPosition: CGPoint = .zero
    
    private var appleMusicURL: URL? {
        URL(string: "https://music.apple.com/us/song/\(song.id)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    Spacer().frame(height: 60)
                    
                    // Album Artwork
                    ZStack(alignment: .topLeading) {
                        let displaySize = geometry.size.width * 0.85
                        let scale = UIScreen.main.scale
                        
                        if let artworkURL = song.artwork?.url(
                            width: Int(displaySize * scale * 2),
                            height: Int(displaySize * scale * 2)
                        ) {
                            CustomAsyncImage(url: artworkURL, isCircle: false)
                                .frame(width: geometry.size.width * 0.85,
                                       height: geometry.size.width * 0.85)
                                .id(song.id)
                        }
                        
                        if !appleMusicSubscription {
                            Text("Preview")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .offset(y: -25)
                        }
                    }
                    
                    Spacer().frame(height: 14)
                    
                    // Title
                    ScrollableText(
                        text: song.title,
                        isAnimating: $animateTitle,
                        scrollSpeed: 47.0
                    )
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .id("title-\(song.id)")
                    
                    Spacer().frame(height: 12)
                    
                    // Artist
                    ScrollableText(
                        text: song.artistName,
                        isAnimating: $animateArtist,
                        scrollSpeed: 47.0
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .id("artist-\(song.id)")
                    
                    Spacer().frame(height: 30)
                    
                    // Controls
                    HStack(spacing: 40) {
                        Button(action: playPreviousSong) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 28))
                                .foregroundColor(networkMonitor.isConnected ? .primary : .gray)
                        }
                        .disabled(!networkMonitor.isConnected)
                        
                        ZStack {
                            if playerIsReady {
                                Button(action: {
                                    togglePlayPause()
                                    
                                    Analytics.logEvent("track_play_pause_tapped", parameters: [
                                        "song_id": song.id.rawValue,
                                        "is_playing": isPlaying
                                    ])
                                }) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.primary)
                                }
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: 60, height: 60)
                        
                        Button(action: playNextSong) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 28))
                                .foregroundColor(networkMonitor.isConnected ? .primary : .gray)
                        }
                        .disabled(!networkMonitor.isConnected)
                    }
                    .padding(.bottom, 22)
                    
                    
                    if networkMonitor.isConnected {
                        
                        Button {
                            // Get the button's position before showing menu
                            if let buttonFrame = getButtonFrame() {
                                menuPosition = CGPoint(
                                    x: buttonFrame.midX,
                                    y: buttonFrame.minY
                                )
                            }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showActionsMenu = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.primary)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(
                                                key: ButtonPositionKey.self,
                                                value: geo.frame(in: .global)
                                            )
                                    }
                                )
                        }
                        .padding(.top, 6)
                        
                    }
                    
                    Spacer()
                    
                    // Apple Music Link
                    if let appleMusicURL, !appleMusicSubscription {
                        Link(destination: appleMusicURL) {
                            Image("AppleMusicBadge")
                                .resizable()
                                .scaledToFit()
                                .frame(height: min(geometry.size.width * 0.09, 59))
                                .padding(.top, 10)
                        }
                        .padding()
                        .simultaneousGesture(TapGesture().onEnded {
                            Analytics.logEvent("apple_music_link_tapped", parameters: [
                                "source": "track_detail",
                                "song_id": song.id.rawValue
                            ])
                        })
                    }
                }
                .onPreferenceChange(ButtonPositionKey.self) { frame in
                    if let frame = frame {
                        menuPosition = CGPoint(
                            x: frame.midX,
                            y: frame.minY
                        )
                    }
                }
                .padding(.horizontal)
                .frame(width: geometry.size.width, height: geometry.size.height)
                
                VStack {
                    HStack {
                        Spacer()
                        
                        HStack(spacing: 18) {
                            
                            // Favorite Button
                            if networkMonitor.isConnected {
                                Button(action: {
                                    let wasFavorite = favoritesManager.isFavorite(song)

                                        // capture index BEFORE mutation
                                        let currentIndex = favoritesManager.favoriteSongs.firstIndex(where: {
                                            $0.id == song.id
                                        })

                                        favoritesManager.toggleFavorite(song)

                                        if wasFavorite {

                                            Task {
                                                try? await Task.sleep(nanoseconds: 200_000_000)

                                                await MainActor.run {
                                                    playerManager.handleCurrentFavoriteRemoved(
                                                        removedSong: song,
                                                        removedIndex: currentIndex,
                                                        favoritesManager: favoritesManager,
                                                        networkMonitor: networkMonitor
                                                    )
                                                }
                                            }
                                        }

                                    Analytics.logEvent("favorite_toggled", parameters: [
                                        "song_id": song.id.rawValue,
                                        "is_favorite": favoritesManager.isFavorite(song)
                                    ])

                                }) {
                                    Image(systemName: favoritesManager.isFavorite(song) ? "star.fill" : "star")
                                        .font(.system(size: 24))
                                        .foregroundColor(favoritesManager.isFavorite(song) ? .yellow : .primary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                            }
                            
                            // Close Button
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                        .padding(.trailing, 6)
                    }
                    
                    Spacer()
                }
                if showActionsMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showActionsMenu = false
                        }
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        Button {
                            showActionsMenu = false
                            Analytics.logEvent("view_artist_tapped", parameters: [
                                "song_id": song.id.rawValue,
                                "artist_name": song.artistName
                            ])
                            openArtist()
                        } label: {
                            Label("View Artist", systemImage: "music.mic")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .foregroundStyle(Color.primary)
                        }
                        
                        if isPlayingFromAlbum {
                            Divider()
                            
                            Button {
                                showActionsMenu = false
                                openAlbum()
                            } label: {
                                Label("View Album", systemImage: "square.stack")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .frame(maxWidth: 240)
                    .position(
                        x: menuPosition.x,
                        y: menuPosition.y - 60 // Offset above the button
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .frame(width: geometry.size.width, height: geometry.size.height)
            
            
            // 🔥 Track screen view
            .onAppear {
                Analytics.logEvent("track_detail_viewed", parameters: [
                    "song_id": song.id.rawValue,
                    "song_title": song.title,
                    "artist_name": song.artistName
                ])
            }
            
            .onChange(of: playerManager.currentlyPlayingSong) {
                if playerManager.currentlyPlayingSong == nil {
                    dismiss()
                }
            }
        }
    }
    
    private func getButtonFrame() -> CGRect? {
        // Helper method to get the button's frame
        return nil // Will be handled by preference key
    }
    
    private func openAlbum() {
        Analytics.logEvent(
            "view_album_tapped",
            parameters: [
                "song_id": song.id.rawValue,
                "album_id": albumWithTracks?.album.id.rawValue ?? ""
            ]
        )
        
        guard let albumWithTracks,
              albumWithTracks.tracks.contains(where: {
                  $0.id == song.id
              }) else {
            return
        }
        
        let albumID = albumWithTracks.album.id
        
        let isAlbumOnTop: Bool = {
            switch activeTab {
            case .home:
                guard let lastRoute = homeNavigationPath.last else { return false }
                if case .album(let routeID) = lastRoute {
                    return routeID == albumID
                }
                
            case .search:
                guard let lastRoute = searchNavigationPath.last else { return false }
                if case .album(let routeID) = lastRoute {
                    return routeID == albumID
                }
                
            case .favorites:
                guard let lastRoute = favoritesNavigationPath.last else { return false }
                if case .album(let routeID) = lastRoute {
                    return routeID == albumID
                }
            }
            
            return false
        }()
        
        if isAlbumOnTop {
            dismiss()
            return
        }
        
        switch activeTab {
            
        case .home:
            homeNavigationPath.append(
                Route.album(albumWithTracks.album.id)
            )
            
        case .favorites:
            favoritesNavigationPath.append(
                Route.album(albumWithTracks.album.id)
            )
            
        case .search:
            searchNavigationPath.append(
                Route.album(albumWithTracks.album.id)
            )
        }
        
        dismiss()
    }
    
    private func fetchSongWithArtists() async throws -> Song {
        var request = MusicCatalogResourceRequest<Song>(
            matching: \.id,
            equalTo: song.id
        )
        
        request.properties = [.artists]
        request.limit = 1
        
        let response = try await request.response()
        
        guard let fullSong = response.items.first else {
            throw URLError(.badServerResponse)
        }
        
        return fullSong
    }
    
    private func openArtist() {
        Task {
            do {
                
                dismiss()
                
                let fullSong = try await fetchSongWithArtists()
                
                guard let artist = fullSong.artists?.first else {
                    print("No artist found even after full fetch")
                    return
                }
                
                let artistID = artist.id
                
                await MainActor.run {
                    
                    switch activeTab {
                    case .home:
                        homeNavigationPath.append(.artist(artistID))
                    case .search:
                        searchNavigationPath.append(.artist(artistID))
                    case .favorites:
                        favoritesNavigationPath.append(.artist(artistID))
                    }
                    
                    Analytics.logEvent("artist_opened", parameters: [
                        "artist_id": artist.id.rawValue,
                        "artist_name": artist.name,
                        "song_id": song.id.rawValue
                    ])
                    
                }
                
            } catch {
                print("Error fetching song with artists: \(error)")
            }
        }
    }
    
    private func playNextSong() {
        Analytics.logEvent("track_skipped_next", parameters: [
            "song_id": song.id.rawValue
        ])
        
        guard networkMonitor.isConnected else { return }
        
        if appleMusicSubscription {
            let player = ApplicationMusicPlayer.shared
            Task {
                try? await player.skipToNextEntry()
            }
            return
        }
        
        animateTitle = false
        animateArtist = false
        
        let currentList: [Song] = {
            switch playerManager.playbackSource {
            case .album:
                return albumWithTracks?.tracks ?? playerManager.lastPlayedSongs
            case .favorites:
                return favoritesManager.favoriteSongs
            case .home, .search, .artist, .none:
                return playerManager.lastPlayedSongs
            }
        }()
        
        guard let currentIndex = currentList.firstIndex(where: { $0.id == song.id }) else { return }
        
        for nextIndex in (currentIndex + 1)..<currentList.count {
            let nextSong = currentList[nextIndex]
            let isPlayable = (nextSong.releaseDate == nil || nextSong.releaseDate! <= Date())
            && nextSong.playParameters != nil
            
            if isPlayable {
                playerManager.playSong(nextSong, from: currentList)
                return
            }
        }
    }
    
    private func playPreviousSong() {
        Analytics.logEvent("track_skipped_previous", parameters: [
            "song_id": song.id.rawValue
        ])
        
        guard networkMonitor.isConnected else { return }
        
        if appleMusicSubscription {
            let player = ApplicationMusicPlayer.shared
            Task {
                try? await player.skipToPreviousEntry()
            }
            return
        }
        
        animateTitle = false
        animateArtist = false
        
        let currentList: [Song] = {
            switch playerManager.playbackSource {
            case .album:
                return albumWithTracks?.tracks ?? playerManager.lastPlayedSongs
            case .favorites:
                return favoritesManager.favoriteSongs
            case .home, .search, .artist, .none:
                return playerManager.lastPlayedSongs
            }
        }()
        
        guard let currentIndex = currentList.firstIndex(where: { $0.id == song.id }) else { return }
        
        for previousIndex in stride(from: currentIndex - 1, through: 0, by: -1) {
            let prevSong = currentList[previousIndex]
            let isPlayable = (prevSong.releaseDate == nil || prevSong.releaseDate! <= Date())
            && prevSong.playParameters != nil
            
            if isPlayable {
                playerManager.playSong(prevSong, from: currentList)
                return
            }
        }
    }
}

// Preference key to track button position
struct ButtonPositionKey: PreferenceKey {
    static var defaultValue: CGRect?
    
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
