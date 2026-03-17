//
//  DailyVerseManager.swift
//  TruWord Music
//
//  Created by Dillon Davis on 3/16/26.
//

import Foundation
import SwiftUI

struct Verse: Identifiable, Codable {
    let id = UUID() // auto-generated, not from JSON
    let reference: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case reference, text // ignore id in JSON
    }
}

final class DailyVerseManager: ObservableObject {
    @Published var verse: Verse?

    private var verses: [Verse] = []
    private var lastDayOfYear: Int?

    init() {
        loadVerses()
        pickDailyVerse()
    }

    /// Load verses from JSON file in app bundle
    private func loadVerses() {
        guard let url = Bundle.main.url(forResource: "verses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([Verse].self, from: data) else {
            print("Failed to load verses.json")
            return
        }
        self.verses = loaded
    }

    /// Pick a verse based on the current day
    func pickDailyVerse() {
        guard !verses.isEmpty else { return }

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1

        let index = dayOfYear % verses.count
        self.verse = verses[index]
        lastDayOfYear = dayOfYear
    }

    /// Called when user pulls to refresh
    func refreshIfNewDay() {
        let currentDay = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1

        if currentDay != lastDayOfYear {
            pickDailyVerse()
            print("New day detected. Verse updated.")
        } else {
            print("Same day. Verse stays the same.")
        }
    }
}
