//
//  TrackDetailView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

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
    @Binding var searchNavigationPath:NavigationPath
    
    @Environment(\.dismiss) private var dismiss
    
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
                            if let albumWithTracks,
                               albumWithTracks.tracks.contains(where: { $0.id == song.id }) {
                                
                                switch activeTab {
                                case .home:
                                    if homeNavigationPath.isEmpty || selectedAlbum?.id != albumWithTracks.album.id {
                                        homeNavigationPath.append(albumWithTracks.album)
                                        print("1 home \(homeNavigationPath.isEmpty) \(selectedAlbum?.id != albumWithTracks.album.id)")
                                    } else {
                                        print("2 home \(homeNavigationPath.isEmpty) \(selectedAlbum?.id != albumWithTracks.album.id)")
                                    }
                                case .search:
                                    if searchNavigationPath.isEmpty || selectedAlbum?.id != albumWithTracks.album.id {
                                        searchNavigationPath.append(albumWithTracks.album)
                                        print("1 search \(searchNavigationPath.isEmpty) \(selectedAlbum?.id != albumWithTracks.album.id)")
                                    } else {
                                        print("2 search \(searchNavigationPath.isEmpty) \(selectedAlbum?.id != albumWithTracks.album.id)")
                                    }
                                }

                            }
                            dismiss()
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
    
    private func playNextSong() {
        guard networkMonitor.isConnected else { return }
        animateTitle = false
        animateArtist = false
        
        // Determine which list to use
        let currentList: [Song]
        if isPlayingFromAlbum, let album = albumWithTracks {
            currentList = album.tracks
        } else {
            currentList = songs
        }
        
        guard let currentIndex = currentList.firstIndex(where: { $0.id == song.id }) else { return }
        
        var nextIndex = currentIndex + 1
        while nextIndex < currentList.count {
            let nextSong = currentList[nextIndex]
            let isPlayable = (nextSong.releaseDate.map { $0 <= Date() } ?? false) && nextSong.playParameters != nil
            if isPlayable {
                playerManager.playSong(nextSong, from: currentList)
                return
            }
            nextIndex += 1
        }
    }

    private func playPreviousSong() {
        guard networkMonitor.isConnected else { return }
        animateTitle = false
        animateArtist = false
        
        // Determine which list to use
        let currentList: [Song]
        if isPlayingFromAlbum, let album = albumWithTracks {
            currentList = album.tracks
        } else {
            currentList = songs
        }
        
        guard let currentIndex = currentList.firstIndex(where: { $0.id == song.id }) else { return }
        
        var previousIndex = currentIndex - 1
        while previousIndex >= 0 {
            let previousSong = currentList[previousIndex]
            let isPlayable = (previousSong.releaseDate.map { $0 <= Date() } ?? false) && previousSong.playParameters != nil
            if isPlayable {
                playerManager.playSong(previousSong, from: currentList)
                return
            }
            previousIndex -= 1
        }
    }

    

}

