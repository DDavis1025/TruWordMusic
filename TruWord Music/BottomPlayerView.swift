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
        HStack {
            let screenWidth = UIScreen.main.bounds.width
            let songArtworkSize = min(max(screenWidth * 0.14, 40), 90) // Between 40-90pt
            
            // Song Artwork
            if let artworkURL = song.artwork?.url(width: 120, height: 120) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: songArtworkSize, height: songArtworkSize)
                    .clipped()
                    .cornerRadius(8)
            }
            
            // Song Title & Artist
            VStack(alignment: .leading) {
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
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}


