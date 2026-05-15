//
//PlayerManager.swift
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
}

enum PlayerLoadingState {
    case idle
    case loading
    case ready
    case failed
}


@MainActor
class PlayerManager: ObservableObject {
    // MARK: - Published Properties
    let networkMonitor: NetworkMonitor
    @Published var currentlyPlayingSong: Song? = nil
    @Published var isPlaying: Bool = false
    @Published var playerIsReady: Bool = true   // Apple Music (MusicKit)
    @Published var previewState: PlayerLoadingState = .idle
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
    
    // MARK: - Private
    private var audioPlayer: AVPlayer?
    private var previewDidEnd: Bool = false
    private var playbackObservationTask: Task<Void, Never>?
    private var playerStateTask: Task<Void, Never>?
    private var playerPreparationTask: Task<Void, Never>?
    private var previewStatusObservation: NSKeyValueObservation?
    private var previewReadyTimeoutTask: Task<Void, Never>?
    
    // ✅ Track playback state across background/foreground
    private var wasPlayingBeforeBackground: Bool = false
    
    init(networkMonitor: NetworkMonitor) {
        self.networkMonitor = networkMonitor
    }
    
    // MARK: - Background / Foreground
    
    func onAppBackground() {
        let player = ApplicationMusicPlayer.shared
        wasPlayingBeforeBackground = (player.state.playbackStatus == .playing)
    }
    
    func onAppForeground() {
        Task {
            let previousStatus = appleMusicSubscription
            await checkAppleMusicStatus()
            refreshCurrentSong()
            await waitForAppleMusicStatusUpdate(previousStatus: previousStatus)
        }
    }
    
    @MainActor
    private func waitForAppleMusicStatusUpdate(previousStatus: Bool, maxRetries: Int = 14) async {
        for _ in 0..<maxRetries {
            await checkAppleMusicStatus()
            
            // If the status changed compared to before, stop waiting
            if appleMusicSubscription != previousStatus {
                if appleMusicSubscription {
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
                audioPlayer?.pause()
                audioPlayer = nil
                previewStatusObservation = nil
                playWithApplicationMusicPlayer(
                    song,
                    songs: validSongs,
                    albumWithTracks: albumWithTracks,
                    playFromAlbum: playFromAlbum
                )
            } else {
                playWithPreview(song, songs: validSongs, networkMonitor: networkMonitor)
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
                Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    await MainActor.run {
                        self.audioPlayer?.play()
                    }
                }
                isPlaying = true
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
    }
    
    
    func stopAndReplaceAVPlayer() {
        let player = ApplicationMusicPlayer.shared
        
        audioPlayer?.pause()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        previewDidEnd = false
        
        if let currentSong = currentlyPlayingSong {
            if player.state.playbackStatus == .stopped || player.queue.entries.isEmpty {
                // ✅ Use last known context instead of empty
                playSong(
                    currentSong,
                    from: lastPlayedSongs,
                    albumWithTracks: lastAlbumWithTracks,
                    playFromAlbum: lastPlayFromAlbum
                )
            } else {
                playerPreparationTask?.cancel()
                playerPreparationTask = Task { @MainActor in
                    await ensurePlayerIsReadyAndPlays(
                        song: currentlyPlayingSong,
                        songs: lastPlayedSongs,
                        albumWithTracks: lastAlbumWithTracks,
                        playFromAlbum: lastPlayFromAlbum
                    )
                }
            }
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
        }
        
        guard let startIndex = queueSongs.firstIndex(of: song) else {
            print("ERROR: Song not found in queueSongs! Falling back to single song.")
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            startPlayback()
            return
        }
        
        let queue = ApplicationMusicPlayer.Queue(for: queueSongs, startingAt: queueSongs[startIndex])
        player.queue = queue
        
        observePlaybackState(
            songs: queueSongs,
            albumWithTracks: albumWithTracks,
            playFromAlbum: playFromAlbum
        )
        
        startPlayback()
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
        networkMonitor: NetworkMonitor?
    ) {
        guard let previewURL = song.previewAssets?.first?.url else {
            print("No preview available for song: \(song.title)")
            clearApplicationMusicPlayer()
            previewState = .failed
            return
        }

        previewDidEnd = false
        audioPlayer?.pause()

        // cleanup old preview state
        previewStatusObservation = nil
        previewReadyTimeoutTask?.cancel()

        self.lastPlayedSongs = songs
        self.lastPlayFromAlbum = false
        self.lastAlbumWithTracks = nil

        // UI state
        Task { @MainActor in
            self.previewState = .loading
        }
        self.isPlaying = false

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

        guard let audioPlayer else {
            previewState = .failed
            return
        }

        let item = audioPlayer.currentItem

        // MARK: - STATUS OBSERVER
        if let item {
            previewStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self else { return }

                Task { @MainActor in
                    switch item.status {
                    case .readyToPlay:
                        self.previewState = .ready
                        self.isPlaying = true

                    case .failed:
                        self.previewState = .failed
                        self.isPlaying = false

                    default:
                        break
                    }
                }
            }
        }

        // MARK: - SAFETY TIMEOUT (prevents stuck loader)
        previewReadyTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            guard let self else { return }

            await MainActor.run {
                if self.previewState == .loading {
                    self.previewState = .ready
                }
            }
        }

        // MARK: - END OBSERVER
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

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                self.audioPlayer?.play()
            }
        }

        self.currentlyPlayingSong = song

        clearApplicationMusicPlayer()
    }
    
    private func previewDidEnd(player: AVPlayer) {
        guard networkMonitor.isConnected else {
            isPlaying = false
            player.seek(to: .zero)
            return
        }
        
        guard let currentSong = currentlyPlayingSong else { return }
        
        previewDidEnd = true
        
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
            isPlaying = false
            player.seek(to: .zero)
            previewState = .idle
            audioPlayer?.pause()
            audioPlayer = nil
            previewStatusObservation = nil
            previewReadyTimeoutTask?.cancel()
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
        
        if player.queue.currentEntry == nil {
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
    private func startPlaybackAndMarkReady(forcePlay: Bool = false) async {
        let player = ApplicationMusicPlayer.shared
        do {
            try await player.prepareToPlay()
            
            // Play if either:
            // 1. It was playing before backgrounding
            // 2. User just clicked play (forcePlay)
            if wasPlayingBeforeBackground || forcePlay {
                try await player.play()
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
        }

        previewStatusObservation = nil
        previewReadyTimeoutTask?.cancel()
        previewReadyTimeoutTask = nil

        previewState = .idle
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
            
            while true {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
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
                            previousSong = matchedSong
                            currentlyPlayingSong = matchedSong
                            isPlaying = true
                        }
                    default: break
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
}
