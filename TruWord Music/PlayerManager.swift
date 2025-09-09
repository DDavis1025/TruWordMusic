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
    @Published var currentlyPlayingSong: Song? = nil
    @Published var isPlaying: Bool = false
    @Published var playerIsReady: Bool = true
    @Published var isPlayingFromAlbum: Bool = false
    @Published var albumWithTracks: AlbumWithTracks?
    @Published var appleMusicSubscription: Bool = false
    @Published var showTrackDetail: Bool = false
    @Published var selectedAlbum: Album? = nil
    // MARK: - Private
    private var audioPlayer: AVPlayer?
    private var previewDidEnd: Bool = false
    private var playbackObservationTask: Task<Void, Never>?
    private var playerStateTask: Task<Void, Never>?
    private var playerPreparationTask: Task<Void, Never>?
    
    // MARK: - Public API
    
    func playSong(_ song: Song, from songs: [Song], albumWithTracks: AlbumWithTracks? = nil, playFromAlbum: Bool = false, networkMonitor: NetworkMonitor? = nil) {
        Task {
            await checkAppleMusicStatus()
            
            if appleMusicSubscription {
                playWithApplicationMusicPlayer(song, songs: songs, albumWithTracks: albumWithTracks, playFromAlbum: playFromAlbum)
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
    
    // MARK: - Helpers
    
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
    
    private func playWithApplicationMusicPlayer(_ song: Song, songs: [Song], albumWithTracks: AlbumWithTracks?, playFromAlbum: Bool) {
        let player = ApplicationMusicPlayer.shared
        let queueSongs: [Song]
        
        if let albumWithTracks, albumWithTracks.tracks.contains(song), playFromAlbum {
            queueSongs = albumWithTracks.tracks
        } else {
            queueSongs = songs
        }
        
        guard let startIndex = queueSongs.firstIndex(of: song) else { return }
        
        let orderedQueue = Array(queueSongs[startIndex...]) + Array(queueSongs[..<startIndex])
        player.queue = ApplicationMusicPlayer.Queue(for: orderedQueue)
        
        Task { @MainActor in
            self.currentlyPlayingSong = song
        }
        
        if !previewDidEnd {
            playerPreparationTask?.cancel()
            playerPreparationTask = Task { await ensurePlayerPlays() }
        } else {
            playerPreparationTask?.cancel()
            previewDidEnd = false
            playerPreparationTask = Task { await ensurePlayerIsReady() }
        }
        
        isPlaying = true
        observePlaybackState(songs: songs, albumWithTracks: albumWithTracks, playFromAlbum: playFromAlbum)
    }
    
    func playWithPreview(_ song: Song, networkMonitor: NetworkMonitor?) {
        guard let previewURL = song.previewAssets?.first?.url else {
            clearApplicationMusicPlayer()
            return
        }
        
        previewDidEnd = false
        audioPlayer?.pause()
        
        if let currentItem = audioPlayer?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        }
        
        audioPlayer = AVPlayer(url: previewURL)
        
        if let playerItem = audioPlayer?.currentItem {
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.previewDidEnd(player: self.audioPlayer!)
                }
            }
        }
        
        audioPlayer?.play()
        
        Task { @MainActor in
            self.currentlyPlayingSong = song
            self.isPlaying = true
        }
        
        clearApplicationMusicPlayer()
    }

    
    private func previewDidEnd(player: AVPlayer) {
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


