//
//  SimilarArtistCarouselItemView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 6/4/26.
//

import SwiftUI
import MusicKit

struct SimilarArtistCarouselItemView: View {
    let artist: Artist

    var body: some View {

        VStack(spacing: 6) {

            let size: CGFloat = 90
            let scale = UIScreen.main.scale
            let pixelSize = Int(size * scale * 2)

            let artworkURL = artist.artwork?.url(width: pixelSize, height: pixelSize)

            CustomAsyncImage(url: artworkURL, isCircle: true)
                .frame(width: size, height: size)

            Text(artist.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 100)
        }
    }
}
