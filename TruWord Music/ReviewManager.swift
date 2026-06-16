import StoreKit
import UIKit

enum ReviewManager {

    private static let songsPlayedKey = "songsPlayedCount"
    private static let daysUsedKey = "daysUsed"
    private static let lastOpenDateKey = "lastOpenDate"
    private static let reviewRequestedKey = "reviewRequested"
    private static let reviewPendingKey = "reviewPending"

    private static var sessionSongCount = 0
    private static var hasRequestedThisSession = false

    static func recordAppOpen() {
        sessionSongCount = 0
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
    }

    static func recordSongPlayed() {
        let defaults = UserDefaults.standard

        let count = defaults.integer(forKey: songsPlayedKey) + 1
        defaults.set(count, forKey: songsPlayedKey)

        sessionSongCount += 1
    }

    static func shouldShowReviewPrompt() -> Bool {
        let defaults = UserDefaults.standard

        let songsPlayed = defaults.integer(forKey: songsPlayedKey)
        let daysUsed = defaults.integer(forKey: daysUsedKey)
        let reviewRequested = defaults.bool(forKey: reviewRequestedKey)

        return songsPlayed >= 10 &&
               daysUsed >= 3 &&
               sessionSongCount >= 3 &&
               !reviewRequested &&
               !hasRequestedThisSession
    }

    static func requestReview() {
        let defaults = UserDefaults.standard

        hasRequestedThisSession = true
        defaults.set(true, forKey: reviewRequestedKey)

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        Task { @MainActor in
            AppStore.requestReview(in: scene)
        }
    }

    // Optional helper for testing
    static func resetReviewData() {
        let defaults = UserDefaults.standard

        defaults.removeObject(forKey: songsPlayedKey)
        defaults.removeObject(forKey: daysUsedKey)
        defaults.removeObject(forKey: lastOpenDateKey)
        defaults.removeObject(forKey: reviewRequestedKey)

        sessionSongCount = 0
        hasRequestedThisSession = false
    }
    
    static func markReviewPending() {
        UserDefaults.standard.set(true, forKey: reviewPendingKey)
    }

    static func showPendingReviewIfNeeded() {
        let defaults = UserDefaults.standard

        guard defaults.bool(forKey: reviewPendingKey) else { return }

        defaults.set(false, forKey: reviewPendingKey)

        requestReview()
    }
}
