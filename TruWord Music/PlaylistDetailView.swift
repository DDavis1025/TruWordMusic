//
//  PlaylistDetailView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 3/10/26.
//

import SwiftUI
import MusicKit

struct PlaylistDetailView: View {
    let playlist: Playlist
    let playSong: (Track) -> Void
    
    @State private var tracks: [Track] = []
    @State private var isLoadingTracks: Bool = true
    
    @Binding var isPlayingFromAlbum: Bool
    @Binding var playlistWithTracks: PlaylistWithTracks? // separate from albums
    
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    private let bottomPlayerHeight: CGFloat = 70
    
    var body: some View {
        VStack(spacing: 4) {
            // Playlist Artwork
            if let artworkURL = playlist.artwork?.url(width: 350, height: 350) {
                let screenWidth = UIScreen.main.bounds.width
                let size = min(max(screenWidth * 0.5, 150), 300)
                
                CustomAsyncImage(url: artworkURL)
                    .frame(width: size, height: size)
                    .clipped()
                    .cornerRadius(12)
            }
            
            // Playlist Name
            Text(playlist.name)
                .font(.headline)
                .padding(.top, 2)
            
            // Curator
            if let curator = playlist.curatorName {
                Text(curator)
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.48))
            }
            
            // Tracks
            if isLoadingTracks {
                ProgressView("Loading tracks...")
                    .padding()
            } else if tracks.isEmpty {
                Text("No tracks available")
                    .padding()
            } else {
                List {
                    ForEach(tracks, id: \.id) { song in
                        let isPlayable = (song.releaseDate == nil || song.releaseDate! <= Date()) && song.playParameters != nil
                        
                        Button {
                            guard isPlayable && networkMonitor.isConnected else { return }
                            
                            // Build PlaylistWithTracks
                            let songTracks: [Song] = tracks.compactMap { track in
                                if case let .song(song) = track {
                                    return song
                                }
                                return nil
                            }

                            let currentPlaylistWithTracks = PlaylistWithTracks(
                                playlist: playlist,
                                tracks: songTracks
                            )

                            playlistWithTracks = currentPlaylistWithTracks
                            
                            // Play the tapped song
                            playSong(song)
                            isPlayingFromAlbum = true
                        } label: {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundColor(isPlayable && networkMonitor.isConnected ? .primary : .gray)
                                Text(song.artistName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(isPlayable && networkMonitor.isConnected ? Color(white: 0.48) : .gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!isPlayable || !networkMonitor.isConnected)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            }
        }
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchPlaylistTracks()
        }
    }
    
    // MARK: - Fetch Playlist Tracks
    func fetchPlaylistTracks() async {
        isLoadingTracks = true
        defer { isLoadingTracks = false }
        
        do {
            var request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: playlist.id)
            request.properties = [.tracks]
            
            let response = try await request.response()
            guard let fetchedPlaylist = response.items.first, let playlistTracks = fetchedPlaylist.tracks else { return }
            
            tracks = Array(playlistTracks)
        } catch {
            print("Error fetching playlist tracks: \(error)")
            tracks = []
        }
    }
}
