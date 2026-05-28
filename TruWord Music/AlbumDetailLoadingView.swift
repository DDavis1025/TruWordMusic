//
//  AlbumDetailLoadingView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 5/28/26.
//

import SwiftUI
import MusicKit

struct AlbumDetailLoadingView: View {
    let albumID: MusicItemID
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var networkMonitor: NetworkMonitor
    @Binding var navigationPath: [Route]
    @Binding var albumCache: [MusicItemID: Album]
    
    @State private var album: Album?
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let album = album {
                AlbumDetailView(
                    album: album,
                    playSong: { song in
                        
                        playerManager.playbackSource = .album
                        playerManager.isPlayingFromAlbum = true
                        
                        playerManager.playSong(
                            song,
                            from: tracks,
                            albumWithTracks: playerManager.albumWithTracks,
                            playFromAlbum: true,
                            networkMonitor: networkMonitor
                        )
                    },
                    isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                    albumWithTracks: $playerManager.albumWithTracks,
                    networkMonitor: networkMonitor,
                    playerManager: playerManager,
                    navigationPath: $navigationPath
                )
            }
        }
        .task {
            await fetchAlbum()
        }
    }
    
    private func fetchAlbum() async {
        do {
            var request = MusicCatalogResourceRequest<Album>(
                matching: \.id,
                equalTo: albumID
            )
            request.properties = [.tracks, .artists]
            
            let response = try await request.response()
            if let fetchedAlbum = response.items.first {

                self.album = fetchedAlbum
                self.albumCache[albumID] = fetchedAlbum

                self.tracks = await fetchAlbumTracks(album: fetchedAlbum)

                self.isLoading = false

            }
        } catch {
            print("Error fetching album: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func fetchAlbumTracks(album: Album) async -> [Song] {
        do {
            var request = MusicCatalogResourceRequest<Album>(
                matching: \.id,
                equalTo: album.id
            )
            
            request.properties = [.tracks]
            
            let response = try await request.response()
            
            guard let fetchedAlbum = response.items.first,
                  let trackIDs = fetchedAlbum.tracks?.map({ $0.id }) else {
                return []
            }
            
            let songRequest = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                memberOf: trackIDs
            )
            
            let songResponse = try await songRequest.response()
            
            return Array(songResponse.items)
            
        } catch {
            print("Track fetch error: \(error)")
            return []
        }
    }
}

