//
//  SongRowView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

// MARK: - Song Row View

struct SongRowView: View {
    let song: Song
    @Binding var currentPlayingSong: Song?
    var leftPadding: CGFloat = 0 // Default left padding
    var rightPadding: CGFloat = 0 // Default right padding
    
    var body: some View {
        HStack {
            // Album Artwork with configurable left padding
            let screenWidth = UIScreen.main.bounds.width
            let songArtworkSize = min(max(screenWidth * 0.15, 50), 100) // Scales dynamically between 50-100pt
            
            if let artworkURL = song.artwork?.url(width: 150, height: 150) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: songArtworkSize, height: songArtworkSize)
                    .clipped()
                    .cornerRadius(8)
                    .padding(.leading, leftPadding) // Use configurable left padding
            }
            // Song Title and Artist Name with configurable right padding
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                
                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.48))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .padding(.trailing, rightPadding) // Use configurable right padding
            
            Spacer()
            
        }
        .padding(.vertical, 5)
    }
}

