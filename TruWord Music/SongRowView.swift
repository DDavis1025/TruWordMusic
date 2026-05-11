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

        HStack(spacing: 12) {

            // MARK: - Artwork
            if let artworkURL = song.artwork?.url(width: 150, height: 150) {

                CustomAsyncImage(url: artworkURL)
                    .frame(width: 58, height: 58)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                    .padding(.leading, leftPadding)
            }

            // MARK: - Song Info
            VStack(alignment: .leading, spacing: 4) {

                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                Text(song.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .padding(.trailing, rightPadding)

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
