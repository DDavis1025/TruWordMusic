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
    // MARK: - Private
    private var audioPlayer: AVPlayer?
    private var previewDidEnd: Bool = false
    private var playbackObservationTask: Task<Void, Never>?
    private var playerStateTask: Task<Void, Never>?
    private var playerPreparationTask: Task<Void, Never>?
    
    init(networkMonitor: NetworkMonitor) {
        self.networkMonitor = networkMonitor
    }
    
    // MARK: - Public API
    
    // Function to call when the app enters the foreground
    func onAppForeground() {
        Task {
            await checkAppleMusicStatus() // Refresh subscription status
            refreshCurrentSong()
            if appleMusicSubscription {
                await stopAndReplaceAVPlayer()
                monitorMusicPlayerState()
            } else {
                stopApplicationMusicPlayer()
            }
        }
    }
    
    func playSong(_ song: Song, from songs: [Song], albumWithTracks: AlbumWithTracks? = nil, playFromAlbum: Bool = false, networkMonitor: NetworkMonitor? = nil) {
        Task {
            await checkAppleMusicStatus()
            
            // Ensure we have a valid songs array for the queue
            var validSongs = songs
            
            if !playFromAlbum && validSongs.isEmpty {
                // If not playing from album but no songs provided, create a single-song array
                validSongs = [song]
            }
            
            if appleMusicSubscription {
                playWithApplicationMusicPlayer(song, songs: validSongs, albumWithTracks: albumWithTracks, playFromAlbum: playFromAlbum)
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
                } else {
                    try? await player.play()
                }
                
                self.isPlaying = (state == .paused)
            }
        } else {
            guard let audioPlayer else { return }
            if isPlaying {
                audioPlayer.pause()
            } else {
                audioPlayer.play()
            }
            isPlaying.toggle()
        }
    }
    
    func stopApplicationMusicPlayer() {
        let player = ApplicationMusicPlayer.shared
        if player.state.playbackStatus == .playing || player.state.playbackStatus == .paused {
            if !player.queue.entries.isEmpty {
                currentlyPlayingSong = nil
                clearApplicationMusicPlayer()
            }
        }
    }
    
    func stopAndReplaceAVPlayer() async {
        let player = ApplicationMusicPlayer.shared
        await checkAppleMusicStatus()
        
        if appleMusicSubscription {
            audioPlayer?.pause()
            if let currentSong = currentlyPlayingSong,
               player.state.playbackStatus != .playing,
               player.state.playbackStatus != .paused,
               player.queue.entries.isEmpty {
                playSong(currentSong, from: [])
            }
        }
    }
    
    func monitorMusicPlayerState() {
        // Cancel the previous task if it exists
        playerStateTask?.cancel()
        
        // Start a new task
        playerStateTask = Task {
            let player = ApplicationMusicPlayer.shared
            while true {
                // Check for cancellation
                if Task.isCancelled {
                    break
                }
                
                let state = player.state
                DispatchQueue.main.async {
                    self.isPlaying = (state.playbackStatus == .playing)
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
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
    
    // MARK: - Private Methods
    
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
        }

        guard let startIndex = queueSongs.firstIndex(of: song) else {
            print("ERROR: Song not found in queueSongs! Falling back to single song.")
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            startPlayback()
            return
        }

        let orderedQueue = Array(queueSongs[startIndex...]) + Array(queueSongs[..<startIndex])
        player.queue = ApplicationMusicPlayer.Queue(for: orderedQueue)

        // ✅ Start monitoring the queue progression
        observePlaybackState(songs: queueSongs,
                             albumWithTracks: albumWithTracks,
                             playFromAlbum: playFromAlbum)

        startPlayback()
    }

    
    private func startPlayback() {
        if !previewDidEnd {
            playerPreparationTask?.cancel()
            playerPreparationTask = Task { await ensurePlayerPlays() }
        } else {
            playerPreparationTask?.cancel()
            previewDidEnd = false
            playerPreparationTask = Task { await ensurePlayerIsReady() }
        }
        
        isPlaying = true
    }
    
    
    func playWithPreview(_ song: Song, networkMonitor: NetworkMonitor?) {
        guard let previewURL = song.previewAssets?.first?.url else {
            print("No preview available for song: \(song.title)")
            clearApplicationMusicPlayer()
            return
        }
        
        // 2️⃣ Stop any existing preview
        previewDidEnd = false
        audioPlayer?.pause()
        
        if let currentItem = audioPlayer?.currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: currentItem
            )
        }
        
        // 3️⃣ Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session:", error)
        }
        
        // 4️⃣ Initialize AVPlayer
        audioPlayer = AVPlayer(url: previewURL)
        
        guard let audioPlayer = audioPlayer else {
            print("Error: AVPlayer failed to initialize.")
            return
        }
        
        // 5️⃣ Observe end of preview
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
        
        // 6️⃣ Play on main thread
        DispatchQueue.main.async {
            audioPlayer.play()
        }
        
        // 7️⃣ Update state
        Task { @MainActor in
            self.currentlyPlayingSong = song
            self.isPlaying = true
        }
        
        clearApplicationMusicPlayer()
    }
    
    
    
    private func previewDidEnd(player: AVPlayer) {
        guard networkMonitor.isConnected else {
            // No internet: stop playback or just reset preview
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
    
    private func ensurePlayerIsReady() async {
        let player = ApplicationMusicPlayer.shared
        await MainActor.run { self.playerIsReady = false }
        
        while true {
            if Task.isCancelled { return }
            try? await player.prepareToPlay()
            
            if player.state.playbackStatus == .paused {
                await MainActor.run { self.playerIsReady = true }
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    private func ensurePlayerPlays() async {
        let player = ApplicationMusicPlayer.shared
        await MainActor.run { self.playerIsReady = false }
        
        while true {
            if Task.isCancelled { return }
            try? await player.play()
            
            if player.state.playbackStatus == .playing {
                await MainActor.run { self.playerIsReady = true }
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
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
    
    private func observePlaybackState(songs: [Song], albumWithTracks: AlbumWithTracks?, playFromAlbum: Bool) {
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


