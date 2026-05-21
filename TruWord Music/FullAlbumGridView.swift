import SwiftUI
import MusicKit
import FirebaseAnalytics

struct FullAlbumGridView: View {
    let albums: [Album]
    let onAlbumSelected: (Album) -> Void
    let cacheAlbum: (Album) -> Void
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    @State private var searchQuery: String = ""
    
    private let bottomPlayerHeight: CGFloat = 77
    
    var filteredAlbums: [Album] {
        if searchQuery.isEmpty {
            return albums
        } else {
            return albums.filter { album in
                album.title.localizedCaseInsensitiveContains(searchQuery) ||
                album.artistName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let albumSize = max(min(screenWidth * 0.4, 255), 150)

        let columns = [
            GridItem(.adaptive(minimum: albumSize), spacing: 20)
        ]
        
        VStack(alignment: .leading, spacing: 10) {
            
            // MARK: - NO INTERNET
            if !networkMonitor.isConnected {
                VStack(spacing: 8) {
                    Spacer()
                    
                    Text("No Internet connection")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("Your device is not connected to the internet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
            }
            
            // MARK: - EMPTY STATE
            else if filteredAlbums.isEmpty {
                Spacer()
                Text("No albums found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            
            // MARK: - CONTENT
            else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(filteredAlbums, id: \.id) { album in
                            VStack {
                                if let artworkURL = album.artwork?.url(width: 280, height: 280) {
                                    CustomAsyncImage(url: artworkURL)
                                        .frame(width: albumSize, height: albumSize)
                                        .clipped()
                                        .cornerRadius(12)
                                }
                                
                                Text(album.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: albumSize - 20)
                                
                                Text(album.artistName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(width: albumSize - 20)
                            }
                            .onTapGesture {
                                // 🔥 Track album selection
                                Analytics.logEvent("album_selected_from_grid", parameters: [
                                    "album_id": album.id.rawValue,
                                    "album_title": album.title,
                                    "artist_name": album.artistName
                                ])
                                
                                cacheAlbum(album)
                                onAlbumSelected(album)
                            }
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
        .navigationTitle("Top Albums")
        .navigationBarTitleDisplayMode(.inline)
        
        // 🔥 Track grid view
        .onAppear {
            albums.forEach { cacheAlbum($0) }
            
            Analytics.logEvent("album_grid_viewed", parameters: [
                "album_count": filteredAlbums.count
            ])
        }
        
        // 🔥 Track search behavior
        .onChange(of: searchQuery) { _, newValue in
            guard !newValue.isEmpty else { return }

            Analytics.logEvent("album_grid_searched", parameters: [
                "query": newValue
            ])
        }
        
        .if(networkMonitor.isConnected) { view in
            view.searchable(text: $searchQuery)
        }
    }
}
