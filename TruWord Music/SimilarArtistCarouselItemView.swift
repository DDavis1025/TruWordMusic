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

            let screenWidth = UIScreen.main.bounds.width
            let artistSize = max(min(screenWidth * 0.25, 120), 80)

            let pixelSize = Int(artistSize * UIScreen.main.scale * 2)

            let artworkURL = artist.artwork?.url(
                width: pixelSize,
                height: pixelSize
            )

            CustomAsyncImage(url: artworkURL, isCircle: true)
                .frame(width: artistSize, height: artistSize)

            Text(artist.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 100)
        }
    }
}
