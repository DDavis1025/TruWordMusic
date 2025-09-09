//
//  AlbumDetailView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

struct AlbumDetailView: View {
    let album: Album
    let playSong: (Song) -> Void
    
    @State private var tracks: [Song] = []
    @State private var isLoadingTracks: Bool = true
    @Binding var isPlayingFromAlbum: Bool // Added binding
    @Binding var albumWithTracks: AlbumWithTracks?
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    private let bottomPlayerHeight: CGFloat = 60

    
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
                            guard isPlayable && networkMonitor.isConnected else { return }

                            // Build AlbumWithTracks for this album
                            let currentAlbumWithTracks = AlbumWithTracks(album: album, tracks: tracks)
                            
                            // Update binding so playerManager knows the current album
                            albumWithTracks = currentAlbumWithTracks
                            
                            // Play the tapped song
                            playSong(song)
                            
                            // Update UI state
                            isPlayingFromAlbum = true
                            
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
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight) // match BottomPlayerView height
                    }
                }
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchAlbumTracks(album: album)
            await setSelectedAlbum(album: album)
        }
    }
    
    func setSelectedAlbum(album: Album) async {
        playerManager.selectedAlbum = album
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


