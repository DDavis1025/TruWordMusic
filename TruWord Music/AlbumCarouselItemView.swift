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
    var showAlbumYear: Bool = false
    
    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let albumSize = max(min(screenWidth * 0.4, 255), 150)

        let pixelSize = Int(albumSize * UIScreen.main.scale)

        let artworkURL = album.artwork?.url(
            width: pixelSize,
            height: pixelSize
        )

        VStack(spacing: 4) {
            CustomAsyncImage(url: artworkURL, isCircle: false)
                .frame(width: albumSize, height: albumSize)
            
            Text(album.title)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 150)
            
            if showAlbumYear {
                Text(album.releaseDate?.formatted(.dateTime.year()) ?? "—")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            } else {
                Text(album.artistName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            }
        }
        .frame(maxWidth: albumSize)
    }
}
