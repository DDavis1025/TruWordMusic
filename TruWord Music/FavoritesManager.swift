//
//  FavoritesManager.swift
//  TruWord Music
//
//  Created by Dillon Davis on 4/13/26.
//

import Foundation
import MusicKit

@MainActor
class FavoritesManager: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published var favoriteSongs: [Song] = []
    @Published private(set) var favoriteOrder: [String] = []
    
    // Add a callback for when favorites change
    var onFavoritesChanged: (() -> Void)?
    
    private let key = "favorite_song_ids"
    
    init() {
        load()
        Task {
            await fetchFavoriteSongs()
        }
    }
    
    func isFavorite(_ song: Song) -> Bool {
        favoriteIDs.contains(song.id.rawValue)
    }
    
    func toggleFavorite(_ song: Song) {
        let id = song.id.rawValue
        
        if let index = favoriteOrder.firstIndex(of: id) {
            favoriteOrder.remove(at: index)
            favoriteIDs.remove(id)
            favoriteSongs.removeAll { $0.id.rawValue == id }
        } else {
            favoriteOrder.append(id)
            favoriteIDs.insert(id)
        }
        
        save()
        
        Task {
            await fetchFavoriteSongs()
            // Notify that favorites have changed
            await MainActor.run {
                onFavoritesChanged?()
            }
        }
    }
    
    
    private func save() {
        UserDefaults.standard.set(favoriteOrder, forKey: key)
    }
    
    private func load() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            favoriteOrder = saved
            favoriteIDs = Set(saved)
        }
    }
    
    
    func fetchFavoriteSongs() async {
        guard !favoriteIDs.isEmpty else {
            favoriteSongs = []
            return
        }
        
        do {
            let idStrings = favoriteOrder
            let ids = idStrings.map { MusicItemID($0) }
            
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                memberOf: ids
            )
            
            let response = try await request.response()
            let songs = response.items
            
            // Preserve saved order
            favoriteSongs = idStrings.compactMap { id in
                songs.first(where: { $0.id.rawValue == id })
            }
            
        } catch {
            print("ERROR fetching favorites: \(error)")
        }
    }
}

