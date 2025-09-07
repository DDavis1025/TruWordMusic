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
        let albumSize = max(min(screenWidth * 0.4, 255), 150) // Dynamic size: min 150px, max 255px
        
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
                .frame(maxWidth: 150) // Prevent text from stretching too wide
        }
        .frame(maxWidth: albumSize) // Ensure VStack wraps around the image properly
    }
}


