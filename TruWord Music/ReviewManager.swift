//
//  ReviewManager.swift
//  TruWord Music
//
//  Created by Dillon Davis on 6/15/26.
//

import StoreKit
import UIKit

enum ReviewManager {

    private static let songsPlayedKey = "songsPlayedCount"
    private static let daysUsedKey = "daysUsed"
    private static let lastOpenDateKey = "lastOpenDate"
    private static let reviewRequestedKey = "reviewRequested"
    private static var sessionSongCount = 0
    private static var sessionStartDate = Date()
    private static var hasRequestedThisSession = false
    private static let isTestMode = true

    static func recordAppOpen() {
        sessionSongCount = 0
        sessionStartDate = Date()
        hasRequestedThisSession = false
        let defaults = UserDefaults.standard

        let today = Calendar.current.startOfDay(for: Date())

        if let lastDate = defaults.object(forKey: lastOpenDateKey) as? Date {
            let lastDay = Calendar.current.startOfDay(for: lastDate)

            if lastDay != today {
                let daysUsed = defaults.integer(forKey: daysUsedKey)
                defaults.set(daysUsed + 1, forKey: daysUsedKey)
                defaults.set(today, forKey: lastOpenDateKey)
            }
        } else {
            defaults.set(1, forKey: daysUsedKey)
            defaults.set(today, forKey: lastOpenDateKey)
        }

        requestReviewIfNeeded()
    }

    static func recordSongPlayed() {
        let defaults = UserDefaults.standard

        let count = defaults.integer(forKey: songsPlayedKey) + 1
        defaults.set(count, forKey: songsPlayedKey)

        sessionSongCount += 1
        
        print("🎵 SONG PLAYED")
        print("sessionSongCount:", sessionSongCount)

        requestReviewIfNeeded()
    }

    private static func requestReviewIfNeeded() {
        let defaults = UserDefaults.standard

        guard !hasRequestedThisSession else { return }

        let songsPlayed = defaults.integer(forKey: songsPlayedKey)
        let reviewRequested = defaults.bool(forKey: reviewRequestedKey)

        // 🧪 TEST MODE: ignore days + total play requirements
        if isTestMode {
            print("printStatement- 🧪 TEST MODE ACTIVE")
            print("printStatement- sessionSongCount:", sessionSongCount)

            guard sessionSongCount >= 3 else { return }

            print("printStatement- 🚨 REVIEW CONDITIONS MET (TEST)")

            hasRequestedThisSession = true
            defaults.set(true, forKey: reviewRequestedKey)

            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                return
            }

            Task { @MainActor in
                AppStore.requestReview(in: scene)
            }

            return
        }

        // 🔒 PRODUCTION LOGIC (unchanged)
        let daysUsed = defaults.integer(forKey: daysUsedKey)

        guard songsPlayed >= 10 else { return }
        guard daysUsed >= 3 else { return }
        guard sessionSongCount >= 3 else { return }
        guard !reviewRequested else { return }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        hasRequestedThisSession = true
        defaults.set(true, forKey: reviewRequestedKey)

        Task { @MainActor in
            AppStore.requestReview(in: scene)
        }
    }
}
