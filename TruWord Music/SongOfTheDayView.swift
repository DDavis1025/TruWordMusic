//
//  SongOfTheDayView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 4/29/26.
//

import SwiftUI
import MusicKit
import FirebaseAnalytics

struct SongOfTheDayView: View {
    let song: Song?
    let songs: [Song]
    
    @ObservedObject var playerManager: PlayerManager
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let song {
            HStack(spacing: 12) {

                // Artwork
                if let artworkURL = song.artwork?.url(width: 120, height: 120) {
                    CustomAsyncImage(url: artworkURL)
                        .frame(width: 50, height: 50)
                        .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 4) {

                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                        Text("Song of the Day")
                            .foregroundColor(.gray)
                    }
                    .font(.footnote)  // Between caption and subheadline

                    Text(song.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(song.artistName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                .layoutPriority(1)
                
                Spacer(minLength: 8)

                Button {
                    playerManager.playSong(song, from: songs)
                    playerManager.isPlayingFromAlbum = false

                    Analytics.logEvent("song_of_day_played", parameters: [
                        "song_id": song.id.rawValue,
                        "song_name": song.title,
                        "song_artist": song.artistName
                    ])
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            colorScheme == .dark ? Color(.systemGray6) : Color.black
                        )
                        .clipShape(Circle())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading) // ✅ Add this line
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
    }
}
