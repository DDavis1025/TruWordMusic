//
//  PlaylistCarouselItemView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 3/11/26.
//

import SwiftUI
import MusicKit

struct PlaylistCarouselItemView: View {
    let playlist: Playlist
    
    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let itemSize = max(min(screenWidth * 0.4, 255), 150)
        
        VStack {
            if let artworkURL = playlist.artwork?.url(width: 280, height: 280) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: itemSize, height: itemSize)
                    .clipped()
                    .cornerRadius(12)
            }
            
            Text(playlist.name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 150)
        }
        .frame(maxWidth: itemSize)
    }
}


