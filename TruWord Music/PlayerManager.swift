//
//  PlayerManager.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit
import AVFoundation
import FirebaseAnalytics

enum PlaybackSource {
    case none
    case home
    case album
    case favorites
    case search
    case artist
}

enum RepeatMode: String {
    case off
    case all
    case one
}

struct RecentlyPlayedAlbumItem: Codable, Identifiable {
    let id: String
    let title: String
    let artistName: String
}


@MainActor
class PlayerManager: ObservableObject {
    // MARK: - Published Properties
    let networkMonitor: NetworkMonitor
    @Published var currentlyPlayingSong: Song? = nil
    @Published var isPlaying: Bool = false
    @Published var playerIsReady: Bool = true
    @Published var isPlayingFromAlbum: Bool = false
    @Published var albumWithTracks: AlbumWithTracks?
    @Published var appleMusicSubscription: Bool = false
    @Published var showTrackDetail: Bool = false
    @Published var selectedAlbum: Album? = nil
    @Published var songs: [Song] = []
    @Published var lastPlayedSongs: [Song] = []
    @Published var lastAlbumWithTracks: AlbumWithTracks? = nil
    @Published var lastPlayFromAlbum: Bool = false
    @Published var playbackSource: PlaybackSource = .none
    @Published var recentlyPlayedAlbums: [RecentlyPlayedAlbumItem] = []
    @Published var playbackTime: TimeInterval = 0
    @Published var trackDuration: TimeInterval = 0
    @Published var userSkippedSong: Bool = false
    
    @Published var repeatMode: RepeatMode = .off {
        didSet {
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
        }
    }
    
    // MARK: - Private
    private var audioPlayer: AVPlayer?
    private var previewDidEnd: Bool = false
    private var playbackObservationTask: Task<Void, Never>?
    private var playerStateTask: Task<Void, Never>?
    private var playerPreparationTask: Task<Void, Never>?
    private var playbackTimer: Timer?
    private var queueWasExplicitlySet = false
    private var didAutoAdvance = false
    private var didLogThirtySecondPlayback = false
    private var didLogSongCompleted = false
    private var accumulatedPlaybackSeconds: TimeInterval = 0
    private var lastPlaybackTime: TimeInterval = 0
    
    private let recentlyPlayedKey = "recentlyPlayedAlbums"
    private let maxRecentlyPlayed = 40
    
    private weak var favoritesManager: FavoritesManager?
    
    init(networkMonitor: NetworkMonitor, favoritesManager: FavoritesManager) {
        self.networkMonitor = networkMonitor
        self.favoritesManager = favoritesManager
        
        if let savedRepeatMode = UserDefaults.standard.string(forKey: "repeatMode"),
           let mode = RepeatMode(rawValue: savedRepeatMode) {
            self.repeatMode = mode
        }
        
        applySavedRepeatMode()
        
        loadRecentlyPlayedAlbums()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        favoritesManager.onFavoritesChanged = { [weak self] updatedSongs in
            guard let self else { return }
            
            if self.playbackSource == .favorites {
                self.lastPlayedSongs = updatedSongs
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Background / Foreground
    
    func onAppBackground() {
        if !appleMusicSubscription {
            audioPlayer?.pause()
            isPlaying = false
        }
    }
    
    func onAppForeground() {
        Task {
            let previousStatus = appleMusicSubscription
            await checkAppleMusicStatus()
            refreshCurrentSong()
            await waitForAppleMusicStatusUpdate(previousStatus: previousStatus)
            ReviewManager.showPendingReviewIfNeeded()
        }
    }
    
    @MainActor
    private func waitForAppleMusicStatusUpdate(previousStatus: Bool, maxRetries: Int = 14) async {
        for _ in 0..<maxRetries {
            await checkAppleMusicStatus()
            
            // If the status changed compared to before, stop waiting
            if appleMusicSubscription != previousStatus {
                if appleMusicSubscription {
                    UserDefaults.standard.set(false, forKey: "reviewPending")
                    stopAndReplaceAVPlayer()
                } else {
                    stopApplicationMusicPlayer()
                }
                break
            }
            
            // Wait 1 second before retrying
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    // MARK: - Public API
    
    func playSong(
        _ song: Song,
        from songs: [Song],
        albumWithTracks: AlbumWithTracks? = nil,
        playFromAlbum: Bool = false,
        networkMonitor: NetworkMonitor? = nil
    ) {
        Task {
            await checkAppleMusicStatus()
            
            var validSongs = songs
            if !playFromAlbum && validSongs.isEmpty {
                validSongs = [song]
            }
            
            if appleMusicSubscription {
                playWithApplicationMusicPlayer(
                    song,
                    songs: validSongs,
                    albumWithTracks: albumWithTracks,
                    playFromAlbum: playFromAlbum
                )
            } else {
                playWithPreview(song,
                                songs: validSongs,
                                albumWithTracks: albumWithTracks,
                                networkMonitor: networkMonitor)
            }
        }
    }
    
    func togglePlayPause() {
        if appleMusicSubscription {
            Task {
                let player = ApplicationMusicPlayer.shared
                let state = player.state.playbackStatus
                
                if state == .playing {
                    player.pause()
                    await MainActor.run { self.isPlaying = false }
                    Analytics.logEvent("playback_paused", parameters: [
                        "song_id": self.currentlyPlayingSong?.id.rawValue ?? ""
                    ])
                } else {
                    do {
                        try await player.play()
                        await MainActor.run { self.isPlaying = true }
                        Analytics.logEvent("playback_started", parameters: [
                            "song_id": self.currentlyPlayingSong?.id.rawValue ?? "",
                            "source": self.isPlayingFromAlbum ? "album" : "list"
                            
                        ])
                    } catch {
                        print("Failed to play: \(error)")
                        await MainActor.run { self.isPlaying = false }
                        Analytics.logEvent("playback_failed", parameters: [
                            "song_id": self.currentlyPlayingSong?.id.rawValue ?? ""
                        ])
                    }
                }
            }
        } else {
            guard let audioPlayer else { return }
            
            if audioPlayer.timeControlStatus == .playing {
                audioPlayer.pause()
                isPlaying = false
            } else {
                audioPlayer.play()
                isPlaying = true
                print("print: playback started")
                Analytics.logEvent("playback_started", parameters: [
                    "song_id": self.currentlyPlayingSong?.id.rawValue ?? "",
                    "source": "preview"
                ])
            }
        }
    }
    
    func stopApplicationMusicPlayer() {
        currentlyPlayingSong = nil
        clearApplicationMusicPlayer()
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    
    func stopAndReplaceAVPlayer() {
        audioPlayer?.pause()
        audioPlayer = nil
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        previewDidEnd = false
        
        guard let currentSong = currentlyPlayingSong else { return }
        
        Task { @MainActor in
            await ensurePlayerIsReady(
                song: currentSong,
                songs: lastPlayedSongs,
                albumWithTracks: lastAlbumWithTracks,
                playFromAlbum: lastPlayFromAlbum
            )
        }
    }
    
    func monitorMusicPlayerState() {
        playerStateTask?.cancel()
        playerStateTask = Task {
            let player = ApplicationMusicPlayer.shared
            while true {
                if Task.isCancelled { break }
                
                let state = player.state
                DispatchQueue.main.async {
                    self.isPlaying = (state.playbackStatus == .playing)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    
    func refreshCurrentSong() {
        if appleMusicSubscription {
            if let item = ApplicationMusicPlayer.shared.queue.currentEntry?.item {
                switch item {
                case .song(let song):
                    currentlyPlayingSong = song
                default: break
                }
            }
        }
    }
    
    // MARK: - MusicKit Playback
    
    private func playWithApplicationMusicPlayer(
        _ song: Song,
        songs: [Song],
        albumWithTracks: AlbumWithTracks?,
        playFromAlbum: Bool
    ) {
         didLogThirtySecondPlayback = false
         didLogSongCompleted = false
         accumulatedPlaybackSeconds = 0
         lastPlaybackTime = 0
        
        let player = ApplicationMusicPlayer.shared
        let queueSongs: [Song]
        
        if let albumWithTracks,
           albumWithTracks.tracks.contains(song),
           playFromAlbum {
            queueSongs = albumWithTracks.tracks
        } else {
            queueSongs = songs
        }
        
        Task { @MainActor in
            self.currentlyPlayingSong = song
            self.lastPlayedSongs = songs
            self.lastAlbumWithTracks = albumWithTracks
            self.lastPlayFromAlbum = playFromAlbum
            
            if playFromAlbum, let albumWithTracks {
                addRecentlyPlayedAlbum(albumWithTracks.album)
            }
        }
        
        guard let startIndex = queueSongs.firstIndex(of: song) else {
            print("ERROR: Song not found in queueSongs! Falling back to single song.")
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            startPlayback()
            return
        }
        
        let queue = ApplicationMusicPlayer.Queue(for: queueSongs, startingAt: queueSongs[startIndex])
        player.queue = queue
        
        queueWasExplicitlySet = true
        
        observePlaybackState(
            songs: queueSongs,
            albumWithTracks: albumWithTracks,
            playFromAlbum: playFromAlbum
        )
        
        startPlayback()
        startPlaybackTimer()
    }
    
    private func startPlayback() {
        if !previewDidEnd {
            playerPreparationTask?.cancel()
            playerPreparationTask = Task {
                await ensurePlayerIsReadyAndPlays(
                    song: currentlyPlayingSong,
                    songs: lastPlayedSongs,
                    albumWithTracks: lastAlbumWithTracks,
                    playFromAlbum: lastPlayFromAlbum,
                    forcePlay: true
                )
            }
        }
    }
    
    func playWithPreview(
        _ song: Song,
        songs: [Song],
        albumWithTracks: AlbumWithTracks?,
        networkMonitor: NetworkMonitor?
    ) {
        guard let previewURL = song.previewAssets?.first?.url else {
            print("No preview available for song: \(song.title)")
            clearApplicationMusicPlayer()
            return
        }
        
        didLogSongCompleted = false
        didLogThirtySecondPlayback = false
        accumulatedPlaybackSeconds = 0
        lastPlaybackTime = 0
        
        previewDidEnd = false
        audioPlayer?.pause()
        
        self.lastPlayedSongs = songs
        self.lastPlayFromAlbum = albumWithTracks?.tracks.contains(song) == true
        self.lastAlbumWithTracks = albumWithTracks
        
        if let currentItem = audioPlayer?.currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: currentItem
            )
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session:", error)
        }
        
        audioPlayer = AVPlayer(url: previewURL)
        guard let audioPlayer = audioPlayer else {
            print("Error: AVPlayer failed to initialize.")
            return
        }
        
        if let playerItem = audioPlayer.currentItem {
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.previewDidEnd(player: audioPlayer)
                }
            }
        }
        
        DispatchQueue.main.async {
            audioPlayer.play()
            ReviewManager.recordSongPlayed()
            
            print("print: song_started non sub")
            
            Analytics.logEvent("song_started", parameters: [
                "song_id": song.id.rawValue,
                "subscription": false
            ])
        }
        
        startPlaybackTimer()
        
        Task { @MainActor in
            self.currentlyPlayingSong = song
            self.isPlaying = true
            
            if let albumWithTracks {
                addRecentlyPlayedAlbum(albumWithTracks.album)
            }
        }
        
        clearApplicationMusicPlayer()
    }
    
    private func previewDidEnd(player: AVPlayer) {
        guard networkMonitor.isConnected else {
            isPlaying = false
            player.seek(to: .zero)
            return
        }
        
        if ReviewManager.shouldShowReviewPrompt() {
            ReviewManager.requestReview()
        }
        
        guard let currentSong = currentlyPlayingSong else { return }
        
        previewDidEnd = true
        
        if !didLogSongCompleted {

            didLogSongCompleted = true
            
            print("print: song completed preview")

            Analytics.logEvent("song_completed", parameters: [
                "song_id": currentlyPlayingSong?.id.rawValue ?? "",
                "subscription": false
            ])
        }
        
        // ✅ Determine correct list (album OR last played list like favorites)
        let currentList: [Song] = {
            if isPlayingFromAlbum,
               let albumWithTracks,
               albumWithTracks.tracks.contains(currentSong) {
                return albumWithTracks.tracks
            } else {
                return lastPlayedSongs
            }
        }()
        
        if repeatMode == .one {
            playSong(
                currentSong,
                from: currentList,
                albumWithTracks: isPlayingFromAlbum ? albumWithTracks : nil,
                playFromAlbum: isPlayingFromAlbum
            )
            return
        }
        
        // ✅ Find next playable song
        var nextSong: Song? = nil
        
        if let currentIndex = currentList.firstIndex(of: currentSong),
           currentIndex < currentList.count - 1 {
            
            let remainingSongs = currentList[(currentIndex + 1)...]
            
            nextSong = remainingSongs.first {
                ($0.releaseDate == nil || $0.releaseDate! <= Date())
                && $0.playParameters != nil
            }
        }
        
        // ✅ Play next or stop
        if let nextSongToPlay = nextSong {
            playSong(
                nextSongToPlay,
                from: currentList,
                albumWithTracks: isPlayingFromAlbum ? albumWithTracks : nil,
                playFromAlbum: isPlayingFromAlbum
            )
        } else {
            
            if repeatMode == .all,
               let firstSong = currentList.first {
                
                playSong(
                    firstSong,
                    from: currentList,
                    albumWithTracks: isPlayingFromAlbum ? albumWithTracks : nil,
                    playFromAlbum: isPlayingFromAlbum
                )
                
            } else {
                isPlaying = false
                player.seek(to: .zero)
            }
        }
    }
    
    
    @MainActor
    private func ensurePlayerIsReadyAndPlays(
        song: Song?,
        songs: [Song] = [],
        albumWithTracks: AlbumWithTracks? = nil,
        playFromAlbum: Bool = false,
        forcePlay: Bool = false
    ) async {
        let player = ApplicationMusicPlayer.shared
        self.playerIsReady = false
        
        if !queueWasExplicitlySet {
            
            guard let song = song else {
                print("⚠️ No song provided and queue is empty.")
                self.playerIsReady = true
                return
            }
            
            let queueSongs: [Song]
            if let albumWithTracks,
               albumWithTracks.tracks.contains(song),
               playFromAlbum {
                queueSongs = albumWithTracks.tracks
            } else if !songs.isEmpty {
                queueSongs = songs
            } else {
                queueSongs = [song]
            }
            
            guard let startIndex = queueSongs.firstIndex(of: song) else {
                print("ERROR: Song not found in queueSongs! Falling back to single song.")
                player.queue = ApplicationMusicPlayer.Queue(for: [song])
                return await startPlaybackAndMarkReady()
            }
            
            let orderedQueue = Array(queueSongs[startIndex...]) + Array(queueSongs[..<startIndex])
            player.queue = ApplicationMusicPlayer.Queue(for: orderedQueue)
            
            observePlaybackState(
                songs: queueSongs,
                albumWithTracks: albumWithTracks,
                playFromAlbum: playFromAlbum
            )
        }
        
        await startPlaybackAndMarkReady(forcePlay: forcePlay)
        
        monitorMusicPlayerState()
    }
    
    @MainActor
    private func ensurePlayerIsReady(
        song: Song?,
        songs: [Song] = [],
        albumWithTracks: AlbumWithTracks? = nil,
        playFromAlbum: Bool = false
    ) async {
        
        let player = ApplicationMusicPlayer.shared
        self.playerIsReady = false
        
        if player.queue.currentEntry == nil {
            guard let song = song else {
                self.playerIsReady = true
                return
            }
            
            let queueSongs: [Song]
            if let albumWithTracks,
               albumWithTracks.tracks.contains(song),
               playFromAlbum {
                queueSongs = albumWithTracks.tracks
            } else if !songs.isEmpty {
                queueSongs = songs
            } else {
                queueSongs = [song]
            }
            
            guard let startIndex = queueSongs.firstIndex(of: song) else {
                player.queue = ApplicationMusicPlayer.Queue(for: [song])
                self.playerIsReady = true
                return
            }
            
            let orderedQueue = Array(queueSongs[startIndex...]) + Array(queueSongs[..<startIndex])
            player.queue = ApplicationMusicPlayer.Queue(for: orderedQueue)
            
            observePlaybackState(
                songs: queueSongs,
                albumWithTracks: albumWithTracks,
                playFromAlbum: playFromAlbum
            )
        }
        
        do {
            try await player.prepareToPlay()
        } catch {
            print("prepare failed: \(error)")
        }
        
        self.playerIsReady = true
    }
    
    @MainActor
    private func startPlaybackAndMarkReady(forcePlay: Bool = false) async {
        let player = ApplicationMusicPlayer.shared
        do {
            try await player.prepareToPlay()
            
            // Play if either:
            // 1. It was playing before backgrounding
            // 2. User just clicked play (forcePlay)
            if forcePlay {
                try await player.play()
                ReviewManager.recordSongPlayed()
                
                print("print:song started for subscription")
                Analytics.logEvent("song_started", parameters: [
                    "song_id": self.currentlyPlayingSong?.id.rawValue ?? "",
                    "subscription": true
                ])
            }
            
        } catch {
            print("⚠️ Player start failed: \(error)")
            self.playerIsReady = true
            return
        }
        
        // Poll until status is ready
        Task {
            for _ in 0..<10 {
                let status = player.state.playbackStatus
                if status == .playing || status == .paused || status == .stopped {
                    await MainActor.run { self.playerIsReady = true }
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await MainActor.run { self.playerIsReady = true } // failsafe
        }
    }
    
    
    private func clearApplicationMusicPlayer() {
        if !appleMusicSubscription {
            let player = ApplicationMusicPlayer.shared
            player.stop()
            player.queue = .init()
            player.queue.entries.removeAll()
            
            playbackObservationTask?.cancel()
            playerStateTask?.cancel()
            
            queueWasExplicitlySet = false
        }
    }
    
    private func observePlaybackState(
        songs: [Song],
        albumWithTracks: AlbumWithTracks?,
        playFromAlbum: Bool
    ) {

        playbackObservationTask?.cancel()
        playbackObservationTask = Task {
            let player = ApplicationMusicPlayer.shared
            var previousSong: Song? = currentlyPlayingSong

            // NEW: track end detection
            var didFireEndForCurrentSong: Bool = false
            var previousTime: TimeInterval = 0

            while true {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                // MARK: - END DETECTION (Apple Music fix)
                let currentTime = player.playbackTime
                let duration = self.currentlyPlayingSong?.duration ?? 0

                if duration > 0 {

                    // Song restarted (repeat one / restarted from beginning)
                    let didRestart = currentTime < previousTime

                    if didRestart && !didFireEndForCurrentSong {

                        didFireEndForCurrentSong = true

                        let wasSkip = userSkippedSong

                        userSkippedSong = false

                        if !wasSkip {
                            if ReviewManager.shouldShowReviewPrompt() {
                                if UIApplication.shared.applicationState == .active {
                                    ReviewManager.requestReview()
                                } else {
                                    ReviewManager.markReviewPending()
                                }
                            }
                        }
                    }

                    // reset once playback has progressed again
                    if currentTime > 1.0 {
                        didFireEndForCurrentSong = false
                    }
                }

                previousTime = currentTime

                // MARK: - EXISTING QUEUE TRACKING (UNCHANGED LOGIC)
                if let currentEntry = player.queue.currentEntry {
                    switch currentEntry.item {
                    case .song(let song):
                        let matchedSong: Song?

                        if playFromAlbum, let albumWithTracks {
                            matchedSong = albumWithTracks.tracks.first(where: { $0.id == song.id })
                        } else {
                            matchedSong = songs.first(where: { $0.id == song.id })
                        }

                        if let matchedSong, matchedSong != previousSong {

                            let wasSkip = userSkippedSong
                            userSkippedSong = false

                            if !wasSkip {
                                if ReviewManager.shouldShowReviewPrompt() {
                                    if UIApplication.shared.applicationState == .active {
                                        ReviewManager.requestReview()
                                    } else {
                                        ReviewManager.markReviewPending()
                                    }
                                }
                            }
                            
                            // Reset analytics flags for the new song
                            didLogThirtySecondPlayback = false
                            didLogSongCompleted = false
                            accumulatedPlaybackSeconds = 0
                            lastPlaybackTime = 0

                            previousSong = matchedSong
                            currentlyPlayingSong = matchedSong
                            isPlaying = true
                            
                            print("print: song started")
                            
                            Analytics.logEvent("song_started", parameters: [
                                "song_id": self.currentlyPlayingSong?.id.rawValue ?? "",
                                "subscription": true
                            ])
                        }
                    default:
                        break
                    }
                } else {
                    isPlaying = false
                }
            }
        }
    }
    
    func checkAppleMusicStatus() async {
        do {
            let subscription = try await MusicSubscription.current
            appleMusicSubscription = subscription.canPlayCatalogContent
        } catch {
            print("Error checking Apple Music subscription: \(error)")
            appleMusicSubscription = false
        }
    }
    
    @MainActor
    func handleCurrentFavoriteRemoved(
        removedSong: Song,
        removedIndex: Int?,
        favoritesManager: FavoritesManager,
        networkMonitor: NetworkMonitor
    ) {
        
        if appleMusicSubscription {
            let player = ApplicationMusicPlayer.shared
            
            // rebuild queue from updated favorites immediately
            let updatedFavorites = favoritesManager.favoriteSongs
            
            guard !updatedFavorites.isEmpty else {
                player.stop()
                currentlyPlayingSong = nil
                isPlaying = false
                return
            }
            
            player.queue = ApplicationMusicPlayer.Queue(for: updatedFavorites)
        }
        
        guard playbackSource == .favorites,
              currentlyPlayingSong?.id == removedSong.id
        else {
            return
        }
        
        let updatedFavorites = favoritesManager.favoriteSongs
        
        guard !updatedFavorites.isEmpty else {
            currentlyPlayingSong = nil
            isPlaying = false
            
            if appleMusicSubscription {
                ApplicationMusicPlayer.shared.stop()
            } else {
                audioPlayer?.pause()
            }
            return
        }
        
        var nextSong: Song?
        
        if let index = removedIndex {
            // after removal, index shifts left automatically
            let safeIndex = min(index, updatedFavorites.count - 1)
            nextSong = updatedFavorites[safeIndex]
        } else {
            nextSong = updatedFavorites.first
        }
        
        guard let nextSong else { return }
        
        playSong(
            nextSong,
            from: updatedFavorites,
            albumWithTracks: nil,
            playFromAlbum: false,
            networkMonitor: networkMonitor
        )
    }
    
    func toggleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
            
        case .all:
            repeatMode = .one
            
        case .one:
            repeatMode = .off
        }
        
        let player = ApplicationMusicPlayer.shared
        
        switch repeatMode {
        case .off:
            player.state.repeatMode = MusicPlayer.RepeatMode.none
            
        case .all:
            player.state.repeatMode = MusicPlayer.RepeatMode.all
            
        case .one:
            player.state.repeatMode = MusicPlayer.RepeatMode.one
        }
    }
    
    private func applySavedRepeatMode() {
        let player = ApplicationMusicPlayer.shared
        
        switch repeatMode {
        case .off:
            player.state.repeatMode = MusicPlayer.RepeatMode.none
            
        case .all:
            player.state.repeatMode = MusicPlayer.RepeatMode.all
            
        case .one:
            player.state.repeatMode = MusicPlayer.RepeatMode.one
        }
    }
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }
        
        switch type {
        case .began:
            isPlaying = false
            
            if appleMusicSubscription {
                ApplicationMusicPlayer.shared.pause()
            } else {
                audioPlayer?.pause()
            }
            
        case .ended:
            break
            
        @unknown default:
            break
        }
    }
    
    private func addRecentlyPlayedAlbum(_ album: Album) {
        let item = RecentlyPlayedAlbumItem(
            id: album.id.rawValue,
            title: album.title,
            artistName: album.artistName
        )

        recentlyPlayedAlbums.removeAll { $0.id == item.id }
        recentlyPlayedAlbums.insert(item, at: 0)

        if recentlyPlayedAlbums.count > 40 {
            recentlyPlayedAlbums = Array(recentlyPlayedAlbums.prefix(40))
        }

        saveRecentlyPlayedAlbums()
    }
    
    private func saveRecentlyPlayedAlbums() {
        let data = try? JSONEncoder().encode(recentlyPlayedAlbums)
        UserDefaults.standard.set(data, forKey: recentlyPlayedKey)
    }

    private func loadRecentlyPlayedAlbums() {
        guard let data = UserDefaults.standard.data(forKey: recentlyPlayedKey),
              let decoded = try? JSONDecoder().decode([RecentlyPlayedAlbumItem].self, from: data)
        else { return }

        self.recentlyPlayedAlbums = decoded
    }
    
    func startPlaybackTimer() {
        playbackTimer?.invalidate()

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in

                if self.appleMusicSubscription {
                    let player = ApplicationMusicPlayer.shared
                    self.playbackTime = player.playbackTime
                    self.trackDuration = self.currentlyPlayingSong?.duration ?? 0
                } else if let audioPlayer = self.audioPlayer {
                    self.playbackTime = audioPlayer.currentTime().seconds
                    self.trackDuration = audioPlayer.currentItem?.duration.seconds ?? 30
                }
                
                if self.isPlaying {
                    let delta = self.playbackTime - self.lastPlaybackTime
                    
                    // Only count forward movement (not seeking backwards)
                    if delta > 0 && delta < 2 {
                        self.accumulatedPlaybackSeconds += delta
                    }

                    self.lastPlaybackTime = self.playbackTime
                }

                if !self.didLogThirtySecondPlayback &&
                   self.accumulatedPlaybackSeconds >= 30 {

                    self.didLogThirtySecondPlayback = true

                    Analytics.logEvent("song_30_seconds", parameters: [
                        "song_id": self.currentlyPlayingSong?.id.rawValue ?? "",
                        "subscription": self.appleMusicSubscription
                    ])
                }
            }
        }
    }
}
