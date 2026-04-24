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
    @Binding var homeNavigationPath: NavigationPath
    @Binding var searchNavigationPath: NavigationPath
    @Binding var favoritesNavigationPath: NavigationPath
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favoritesManager: FavoritesManager
    
    @State private var animateTitle: Bool = false
    @State private var animateArtist: Bool = false
    
    @State private var albumStack: [Album] = []
    
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
                            CustomAsyncImage(url: artworkURL)
                                .frame(width: geometry.size.width * 0.85,
                                       height: geometry.size.width * 0.85)
                                .clipped()
                                .cornerRadius(8)
                                .id(song.id)
                        }
                        
                        if !appleMusicSubscription {
                            Text("Preview")
                                .font(.caption)
                                .foregroundColor(.gray)
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
                    .foregroundColor(Color(white: 0.48))
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
                    .padding(.bottom, 10)
                    
                    // View Album
                    if isPlayingFromAlbum {
                        Button(action: {
                            
                            Analytics.logEvent("view_album_tapped", parameters: [
                                "song_id": song.id.rawValue,
                                "album_id": albumWithTracks?.album.id.rawValue ?? ""
                            ])
                            
                            if let albumWithTracks,
                               albumWithTracks.tracks.contains(where: { $0.id == song.id }) {
                                
                                switch activeTab {
                                case .home:
                                    homeNavigationPath.append(Route.album(albumWithTracks.album))

                                case .favorites:
                                    favoritesNavigationPath.append(Route.album(albumWithTracks.album))

                                case .search:
                                    searchNavigationPath.append(Route.album(albumWithTracks.album))
                                }
                                dismiss()
                            }
                        }) {
                            if networkMonitor.isConnected {
                                Text("View Album")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.top, 5)
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
                                "song_id": song.id.rawValue
                            ])
                        })
                    }
                }
                
                VStack {
                    HStack {
                        Spacer()
                        
                        HStack(spacing: 18) {
                            
                            // Favorite Button
                            if networkMonitor.isConnected {
                                Button(action: {
                                    favoritesManager.toggleFavorite(song)
                                    
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
        
        let currentList = (isPlayingFromAlbum && albumWithTracks != nil)
            ? albumWithTracks!.tracks
            : playerManager.lastPlayedSongs
        
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
        
        let currentList = (isPlayingFromAlbum && albumWithTracks != nil)
        ? albumWithTracks!.tracks
        : playerManager.lastPlayedSongs
        
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
