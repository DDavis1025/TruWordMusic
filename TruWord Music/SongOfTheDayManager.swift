//
//  SongOfTheDayManager.swift
//  TruWord Music
//
//  Created by Dillon Davis on 4/29/26.
//

import Foundation
import MusicKit

@MainActor
class SongOfTheDayManager: ObservableObject {
    @Published var song: Song?

    private var songs: [Song] = []

    private let orderKey = "song_of_day_order"
    private let lastDayKey = "song_of_day_last_day"
    private let indexKey = "song_of_day_index"

    func loadSongs(_ songs: [Song]) {
        let cleanSongs = songs.filter {
            $0.contentRating != .explicit
        }

        guard !cleanSongs.isEmpty else { return }

        self.songs = cleanSongs
        pickSongForToday()
    }

    private func pickSongForToday() {
        let today = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let lastDay = UserDefaults.standard.integer(forKey: lastDayKey)

        var order = UserDefaults.standard.array(forKey: orderKey) as? [String] ?? []
        var index = UserDefaults.standard.integer(forKey: indexKey)

        // Current valid song IDs
        let validIDs = songs.map { $0.id.rawValue }

        // Remove deleted/unavailable songs from saved order
        order.removeAll { !validIDs.contains($0) }

        // Add any new songs that weren't previously saved
        let missingIDs = validIDs.filter { !order.contains($0) }
        order.append(contentsOf: missingIDs.shuffled())

        // First setup
        if order.isEmpty {
            order = validIDs.shuffled()
            index = 0
        }

        // Prevent index overflow
        if index >= order.count {
            index = 0
        }

        // New day → move forward
        if today != lastDay {
            index += 1

            // Finished cycle → reshuffle
            if index >= order.count {
                order.shuffle()
                index = 0
            }

            UserDefaults.standard.set(today, forKey: lastDayKey)
        }

        // Save updated values
        UserDefaults.standard.set(index, forKey: indexKey)
        UserDefaults.standard.set(order, forKey: orderKey)

        // Pick today's song safely
        let currentID = order[index]

        if let match = songs.first(where: { $0.id.rawValue == currentID }) {
            self.song = match
        } else {
            // Fallback if somehow still invalid
            self.song = songs.randomElement()
        }
    }
}


