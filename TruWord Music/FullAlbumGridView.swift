//
//  FullAlbumGridView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

struct FullAlbumGridView: View {
    let albums: [Album]
    let onAlbumSelected: (Album) -> Void
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    @State private var searchQuery: String = ""
    
    private let bottomPlayerHeight: CGFloat = 70
    
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .bottom) {
                        if playerManager.currentlyPlayingSong != nil {
                            Color.clear.frame(height: bottomPlayerHeight) // leave space for BottomPlayerView
                        }
                    }
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
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
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

