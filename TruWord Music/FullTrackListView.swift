//
//  FullTrackListView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

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


