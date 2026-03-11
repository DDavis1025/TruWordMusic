//
//  TrackDetailView.swift
//  TruWord Music
//
//  Updated to handle albums and playlists
//

import SwiftUI
import MusicKit

struct TrackDetailView: View {
    @Binding var song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumWithTracks: AlbumWithTracks?
    @Binding var playlistWithTracks: PlaylistWithTracks?
    @Binding var songs: [Song]
    @Binding var playerIsReady: Bool
    
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    @Binding var appleMusicSubscription: Bool
    @Binding var selectedAlbum: Album?
    
    @Binding var activeTab: AppTab
    @Binding var homeNavigationPath: NavigationPath
    @Binding var searchNavigationPath: NavigationPath
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var animateTitle: Bool = false
    @State private var animateArtist: Bool = false
    
    private var appleMusicURL: URL? {
        URL(string: "https://music.apple.com/us/song/\(song.id)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    Spacer().frame(height: 60)
                    
                    // Artwork
                    ZStack(alignment: .topLeading) {
                        if let artworkURL = song.artwork?.url(width: Int(geometry.size.width * 1.3),
                                                              height: Int(geometry.size.width * 1.3)) {
                            CustomAsyncImage(url: artworkURL)
                                .frame(width: geometry.size.width * 0.85, height: geometry.size.width * 0.85)
                                .clipped()
                                .cornerRadius(8)
                                .id(song.id)
                        }
                        
                        if !appleMusicSubscription {
                            Text("Preview")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.leading, 0)
                                .offset(y: -25)
                        }
                    }
                    
                    Spacer().frame(height: 14)
                    
                    // Song Title
                    ScrollableText(text: song.title, isAnimating: $animateTitle, scrollSpeed: 47.0)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .id("title-\(song.id)")
                    
                    Spacer().frame(height: 12)
                    
                    // Artist Name
                    ScrollableText(text: song.artistName, isAnimating: $animateArtist, scrollSpeed: 47.0)
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.48))
                        .id("artist-\(song.id)")
                    
                    Spacer().frame(height: 30)
                    
                    // Playback Controls
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
                        .frame(width: 60, height: 60)
                        
                        Button(action: playNextSong) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 28))
                                .foregroundColor(networkMonitor.isConnected ? .primary : .gray)
                        }
                        .disabled(!networkMonitor.isConnected)
                    }
                    .padding(.bottom, 10)
                    
                    // View Album / Playlist Button
                    if isPlayingFromAlbum {
                        Button(action: {
                            navigateToAlbumOrPlaylist()
                            dismiss()
                        }) {
                            Text(networkMonitor.isConnected
                                 ? (playerManager.playlistWithTracks != nil ? "View Playlist" : "View Album")
                                 : "")
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
                    
                    // Apple Music Preview Link
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
                        Button(action: { dismiss() }) {
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
            .onChange(of: playerManager.currentlyPlayingSong) {
                if playerManager.currentlyPlayingSong == nil { dismiss() }
            }
        }
    }
    
    // MARK: - Playback Navigation

    private func playNextSong() {
        guard networkMonitor.isConnected else { return }
        animateTitle = false
        animateArtist = false
        
        if appleMusicSubscription {
            Task { try? await ApplicationMusicPlayer.shared.skipToNextEntry() }
            return
        }
        
        // Determine current list: album tracks, playlist tracks, or just songs
        let currentList: [Song]
        if isPlayingFromAlbum {
            if let albumTracks = albumWithTracks?.tracks {
                currentList = albumTracks
            } else if let playlistTracks = playlistWithTracks?.tracks {
                currentList = playlistTracks
            } else {
                currentList = songs
            }
        } else {
            currentList = songs
        }
        
        guard let currentIndex = currentList.firstIndex(where: { $0.id == song.id }) else { return }
        var nextIndex = currentIndex + 1
        while nextIndex < currentList.count {
            let nextSong = currentList[nextIndex]
            let isPlayable = (nextSong.releaseDate == nil || nextSong.releaseDate! <= Date()) && nextSong.playParameters != nil
            if isPlayable {
                playerManager.playSong(
                    nextSong,
                    from: currentList,
                    albumWithTracks: albumWithTracks,
                    playlistWithTracks: playlistWithTracks,
                    playFromAlbum: isPlayingFromAlbum
                )
                return
            }
            nextIndex += 1
        }
    }

    private func playPreviousSong() {
        guard networkMonitor.isConnected else { return }
        animateTitle = false
        animateArtist = false
        
        if appleMusicSubscription {
            Task { try? await ApplicationMusicPlayer.shared.skipToPreviousEntry() }
            return
        }
        
        let currentList: [Song]
        if isPlayingFromAlbum {
            if let albumTracks = albumWithTracks?.tracks {
                currentList = albumTracks
            } else if let playlistTracks = playlistWithTracks?.tracks {
                currentList = playlistTracks
            } else {
                currentList = songs
            }
        } else {
            currentList = songs
        }
        
        guard let currentIndex = currentList.firstIndex(where: { $0.id == song.id }) else { return }
        var previousIndex = currentIndex - 1
        while previousIndex >= 0 {
            let previousSong = currentList[previousIndex]
            let isPlayable = (previousSong.releaseDate == nil || previousSong.releaseDate! <= Date()) && previousSong.playParameters != nil
            if isPlayable {
                playerManager.playSong(
                    previousSong,
                    from: currentList,
                    albumWithTracks: albumWithTracks,
                    playlistWithTracks: playlistWithTracks,
                    playFromAlbum: isPlayingFromAlbum
                )
                return
            }
            previousIndex -= 1
        }
    }

    
    // MARK: - Navigation
    private func navigateToAlbumOrPlaylist() {
        if let album = albumWithTracks?.album {
            switch activeTab {
            case .home:
                if homeNavigationPath.isEmpty || selectedAlbum?.id != album.id {
                    homeNavigationPath.append(album)
                }
            case .search:
                if searchNavigationPath.isEmpty || selectedAlbum?.id != album.id {
                    searchNavigationPath.append(album)
                }
            }
        } else if let playlist = playlistWithTracks?.playlist {
            switch activeTab {
            case .home:
                homeNavigationPath.append(playlist)
            case .search:
                searchNavigationPath.append(playlist)
            }
        }
    }
}
