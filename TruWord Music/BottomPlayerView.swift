//
//  BottomPlayerView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

struct BottomPlayerView: View {
    let song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    let playerIsReady: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                let screenWidth = UIScreen.main.bounds.width
                let songArtworkSize = min(max(screenWidth * 0.10, 30), 60) // 10% of screen, min 30, max 60

                // Song Artwork
                if let artworkURL = song.artwork?.url(width: 120, height: 120) {
                    CustomAsyncImage(url: artworkURL)
                        .frame(width: songArtworkSize, height: songArtworkSize)
                        .clipped()
                        .cornerRadius(8)
                }

                // Song Title & Artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(song.artistName)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.48))
                        .lineLimit(1)
                }

                Spacer()

                // Play/Pause Button or Loading Indicator
                if playerIsReady {
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                    .disabled(!playerIsReady)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12) // 👈 reduced padding for wider content
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6).opacity(0.974))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal, 7) // 👈 smaller outer inset to give more width
    }
}
