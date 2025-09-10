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
    
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    @State private var searchQuery: String = "" // State for search query
    
    private let bottomPlayerHeight: CGFloat = 60
    
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .bottom) {
                        if playerManager.currentlyPlayingSong != nil {
                            Color.clear.frame(height: bottomPlayerHeight) // leave space for BottomPlayerView
                        }
                    }
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
                                UIApplication.shared.dismissKeyboard()
                                playSong(song)
                                isPlayingFromAlbum = false
                            }
                            .padding(.vertical, 4)
                            .background(Color(.systemBackground))
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
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

extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
