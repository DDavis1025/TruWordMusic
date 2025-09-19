//
//  PlayerManager.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit
import AVFoundation

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
    
    // MARK: - Private
    private var audioPlayer: AVPlayer?
    private var previewDidEnd: Bool = false
    private var playbackObservationTask: Task<Void, Never>?
    private var playerStateTask: Task<Void, Never>?
    private var playerPreparationTask: Task<Void, Never>?
    
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
            await waitForAppleMusicStatusUpdate()
            refreshCurrentSong()
            if appleMusicSubscription {
                await stopAndReplaceAVPlayer()
                monitorMusicPlayerState()
            } else {
                stopApplicationMusicPlayer()
            }
        }
    }
    
    @MainActor
    private func waitForAppleMusicStatusUpdate(maxRetries: Int = 11) async {
        let previousStatus = appleMusicSubscription
        
        for _ in 0..<maxRetries {
            await checkAppleMusicStatus()
            
            // If the status changed compared to before, stop waiting
            if appleMusicSubscription != previousStatus {
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
                playWithPreview(song, networkMonitor: networkMonitor)
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
                } else {
                    do {
                        try await player.play()
                        await MainActor.run { self.isPlaying = true }
                    } catch {
                        print("Failed to play: \(error)")
                        await MainActor.run { self.isPlaying = false }
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
            }
        }
    }
    
    func stopApplicationMusicPlayer() {
        let player = ApplicationMusicPlayer.shared
        // Check if player has something queued and is either playing or paused
        if !player.queue.entries.isEmpty,
           player.state.playbackStatus != .stopped {
            currentlyPlayingSong = nil
            clearApplicationMusicPlayer()
        }
    }

    
    func stopAndReplaceAVPlayer() async {
        let player = ApplicationMusicPlayer.shared
        await checkAppleMusicStatus()
        guard appleMusicSubscription else { return }
        
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
        
        let orderedQueue = Array(queueSongs[startIndex...]) + Array(queueSongs[..<startIndex])
        player.queue = ApplicationMusicPlayer.Queue(for: orderedQueue)
        
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
    
    func playWithPreview(_ song: Song, networkMonitor: NetworkMonitor?) {
        guard let previewURL = song.previewAssets?.first?.url else {
            print("No preview available for song: \(song.title)")
            clearApplicationMusicPlayer()
            return
        }
        
        previewDidEnd = false
        audioPlayer?.pause()
        
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
        }
        
        Task { @MainActor in
            self.currentlyPlayingSong = song
            self.isPlaying = true
        }
        
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
        
        var nextSong: Song?
        if isPlayingFromAlbum, let albumWithTracks, albumWithTracks.tracks.contains(currentSong) {
            if let currentIndex = albumWithTracks.tracks.firstIndex(of: currentSong) {
                let remainingTracks = albumWithTracks.tracks[(currentIndex + 1)...]
                nextSong = remainingTracks.first(where: { $0.releaseDate.map { $0 <= Date() } ?? false })
            }
        }
        
        if let nextSongToPlay = nextSong {
            playSong(nextSongToPlay, from: albumWithTracks?.tracks ?? [])
        } else {
            isPlaying = false
            player.seek(to: .zero)
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
