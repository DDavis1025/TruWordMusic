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
        guard !songs.isEmpty else { return }
        self.songs = songs
        pickSongForToday()
    }

    private func pickSongForToday() {
        let today = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let lastDay = UserDefaults.standard.integer(forKey: lastDayKey)

        var order = UserDefaults.standard.array(forKey: orderKey) as? [String] ?? []
        var index = UserDefaults.standard.integer(forKey: indexKey)

        // First time OR finished cycle → reshuffle
        if order.isEmpty || order.count != songs.count {
            order = songs.map { $0.id.rawValue }.shuffled()
            index = 0
        }

        // New day → move forward
        if today != lastDay {
            index += 1

            // Reset after full cycle
            if index >= order.count {
                order = songs.map { $0.id.rawValue }.shuffled()
                index = 0
            }

            UserDefaults.standard.set(today, forKey: lastDayKey)
            UserDefaults.standard.set(index, forKey: indexKey)
            UserDefaults.standard.set(order, forKey: orderKey)
        }

        // Find today's song
        let currentID = order[index]

        if let match = songs.first(where: { $0.id.rawValue == currentID }) {
            self.song = match
        }
    }
}


