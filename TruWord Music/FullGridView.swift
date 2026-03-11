//
//  FullAlbumGridView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

// MARK: - Protocol for Grid Items
protocol GridItemRepresentable {
    var id: MusicItemID { get }
    var titleText: String { get }
    var subtitleText: String { get }
    var artworkURL: URL? { get }
}

// MARK: - Conform Album & Playlist
extension Album: GridItemRepresentable {
    var titleText: String { self.title }
    var subtitleText: String { self.artistName }
    var artworkURL: URL? { self.artwork?.url(width: 280, height: 280) }
}

extension Playlist: GridItemRepresentable {
    var titleText: String { self.name }
    var subtitleText: String { self.curatorName ?? "" }
    var artworkURL: URL? { self.artwork?.url(width: 280, height: 280) }
}

// MARK: - Generic Full Grid View
struct FullGridView<Item: GridItemRepresentable>: View {
    let items: [Item]
    let onItemSelected: (Item) -> Void
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    @State private var searchQuery: String = ""
    
    private let bottomPlayerHeight: CGFloat = 70
    
    var filteredItems: [Item] {
        if searchQuery.isEmpty {
            return items
        } else {
            return items.filter { $0.titleText.localizedCaseInsensitiveContains(searchQuery) || $0.subtitleText.localizedCaseInsensitiveContains(searchQuery) }
        }
    }
    
    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let itemSize = max(min(screenWidth * 0.4, 255), 150) // dynamic sizing
        let columns = [GridItem(.adaptive(minimum: itemSize), spacing: 20)]
        
        VStack(alignment: .leading, spacing: 10) {
            
            if !networkMonitor.isConnected {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No Internet connection")
                        .font(.headline)
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                    Text("Your device is not connected to the internet")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            } else if filteredItems.isEmpty {
                Spacer()
                Text("No items found")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(filteredItems, id: \.id) { item in
                            VStack {
                                if let url = item.artworkURL {
                                    CustomAsyncImage(url: url)
                                        .frame(width: itemSize, height: itemSize)
                                        .clipped()
                                        .cornerRadius(12)
                                }
                                
                                Text(item.titleText)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: itemSize - 20)
                                
                                Text(item.subtitleText)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .frame(width: itemSize - 20)
                            }
                            .onTapGesture { onItemSelected(item) }
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            }
        }
        .navigationTitle("Top Items")
        .navigationBarTitleDisplayMode(.inline)
        .if(networkMonitor.isConnected) { view in
            view.searchable(text: $searchQuery)
        }
    }
}

