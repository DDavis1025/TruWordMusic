//
//  AlbumCarouselItemView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

struct AlbumCarouselItemView: View {
    let album: Album
    
    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let albumSize = max(min(screenWidth * 0.4, 255), 150)
        
        VStack(spacing: 4) {
            if let artworkURL = album.artwork?.url(width: 280, height: 280) {
                
                CustomAsyncImage(url: artworkURL)
                    .frame(width: albumSize, height: albumSize)
                    .clipped()
                    .cornerRadius(12)
            }
            
            // Album Title
            Text(album.title)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 150)
            
            // ✅ Artist Name
            Text(album.artistName)
                .font(.caption2)
                .foregroundColor(Color(white: 0.48))
                .lineLimit(1)
                .frame(maxWidth: 150)
        }
        .frame(maxWidth: albumSize)
    }
}
