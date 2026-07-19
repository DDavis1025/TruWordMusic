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
    var showReleaseYear: Bool = false

    var body: some View {
        HStack {
            let screenWidth = UIScreen.main.bounds.width
            let songArtworkSize = min(max(screenWidth * 0.15, 50), 100)

            let scale = UIScreen.main.scale
            let pixelSize = Int(songArtworkSize * scale * 2)

            let artworkURL = song.artwork?.url(
                width: pixelSize,
                height: pixelSize
            )

            CustomAsyncImage(url: artworkURL, isCircle: false)
                .frame(width: songArtworkSize, height: songArtworkSize)
                .padding(.leading, leftPadding)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(
                    showReleaseYear
                    ? "\(song.artistName)\(song.releaseDate.map { " · \($0.formatted(.dateTime.year()))" } ?? "")"
                    : song.artistName
                )
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

