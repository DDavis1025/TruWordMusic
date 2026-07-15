//
//  TodaySectionView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 4/29/26.
//

import SwiftUI
import MusicKit
import FirebaseAnalytics

struct TodaySectionView: View {
    @ObservedObject var verseManager: DailyVerseManager
    @ObservedObject var songOfDayManager: SongOfTheDayManager
    @ObservedObject var playerManager: PlayerManager

    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Header
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.secondary)

                Text("Today")
                    .font(.title2)
                    .bold()

                Spacer()

                // 🔄 Refresh Button
                Button {
                    verseManager.refreshIfNewDay()
                    songOfDayManager.loadSongs(songs) // re-checks day internally
                    Analytics.logEvent("today_section_refreshed", parameters: [
                        "has_verse": verseManager.verse != nil,
                        "has_song": songOfDayManager.song != nil
                    ])
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue) // systemBlue
                }
                .buttonStyle(.plain)
            }

            // Verse Card
            VerseCardView(verse: verseManager.verse)

            // Song Card
            SongOfTheDayView(
                song: songOfDayManager.song,
                songs: songs,
                playerManager: playerManager
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
}
