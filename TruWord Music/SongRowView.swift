//
//  SongRowView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit
import FirebaseAnalytics

// MARK: - Song Row View

struct SongRowView: View {
    let song: Song
    @Binding var currentPlayingSong: Song?
    var leftPadding: CGFloat = 0
    var rightPadding: CGFloat = 0

    var body: some View {
        HStack {

            let songArtworkSize: CGFloat = 70
            let scale = UIScreen.main.scale
            let pixelSize = Int(songArtworkSize * scale * 2)

            let artworkURL = song.artwork?.url(width: pixelSize, height: pixelSize)

            CustomAsyncImage(url: artworkURL, isCircle: false)
                .frame(width: songArtworkSize, height: songArtworkSize)
                .padding(.leading, leftPadding)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.trailing, rightPadding)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

