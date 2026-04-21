import SwiftUI
import MusicKit
import FirebaseAnalytics

struct AlbumDetailView: View {
    @State var album: Album
    let playSong: (Song) -> Void
    @State private var tracks: [Song] = []
    @State private var isLoadingTracks: Bool = true
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumWithTracks: AlbumWithTracks?
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    private let bottomPlayerHeight: CGFloat = 70

    var body: some View {
        VStack(spacing: 4) {
            if let artworkURL = album.artwork?.url(width: 350, height: 350) {
                let screenWidth = UIScreen.main.bounds.width
                let albumSize = min(max(screenWidth * 0.5, 150), 300)
                
                CustomAsyncImage(url: artworkURL)
                    .frame(width: albumSize, height: albumSize)
                    .clipped()
                    .cornerRadius(12)
            }
            
            Text(album.title)
                .font(.headline)
                .padding(.top, 2)
            
            Text(album.artistName)
                .font(.subheadline)
                .foregroundColor(Color(white: 0.48))
            
            if let releaseDate = album.releaseDate {
                Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundColor(Color(white: 0.48))
                    .padding(.bottom, 2)
            }
            
            if isLoadingTracks {
                ProgressView("Loading tracks...")
                    .padding()
                    
            } else if tracks.isEmpty {
                Text("No tracks available")
                    .padding()
                    
            } else {
                List {
                    ForEach(tracks, id: \.id) { song in
                        let isPlayable =
                        (song.releaseDate == nil || song.releaseDate! <= Date()) &&
                        song.playParameters != nil
                        
                        Button {
                            guard isPlayable && networkMonitor.isConnected else { return }

                            // 🔥 Track song selection
                            Analytics.logEvent("album_song_selected", parameters: [
                                "song_id": song.id.rawValue,
                                "album_id": album.id.rawValue
                            ])

                            let currentAlbumWithTracks = AlbumWithTracks(album: album, tracks: tracks)
                            albumWithTracks = currentAlbumWithTracks
                            
                            playSong(song)
                            isPlayingFromAlbum = true
                            
                        } label: {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundColor(isPlayable && networkMonitor.isConnected ? .primary : Color(UIColor.lightGray))
                                
                                Text(song.artistName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(isPlayable && networkMonitor.isConnected ? Color(white: 0.48) : Color(UIColor.lightGray))
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!isPlayable || !networkMonitor.isConnected)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        
        // 🔥 Track album viewed
        .onAppear {
            Analytics.logEvent("album_viewed", parameters: [
                "album_id": album.id.rawValue,
                "album_title": album.title,
                "artist_name": album.artistName
            ])
        }
        
        .task {
            await fetchAlbumTracks(album: album)
            await setSelectedAlbum(album: album)
        }
    }
    
    func setSelectedAlbum(album: Album) async {
        playerManager.selectedAlbum = album
    }
    
    func fetchAlbumTracks(album: Album) async {
        do {
            var albumRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: album.id)
            albumRequest.properties = [.tracks]
            
            let albumResponse = try await albumRequest.response()
            
            guard let fetchedAlbum = albumResponse.items.first else {
                print("Error: Album not found.")
                tracks = []
                return
            }
            
            guard let albumTracks = fetchedAlbum.tracks, !albumTracks.isEmpty else {
                print("Error: Album has no tracks.")
                tracks = []
                return
            }
            
            let trackIDs = albumTracks.compactMap { $0.id }
            
            guard !trackIDs.isEmpty else {
                print("Error: No valid track IDs available.")
                return
            }
            
            let songsRequest = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: trackIDs)
            let songResponse = try await songsRequest.response()
            
            tracks = Array(songResponse.items)
            
            // 🔥 Track tracks loaded
            Analytics.logEvent("album_tracks_loaded", parameters: [
                "album_id": album.id.rawValue,
                "track_count": tracks.count
            ])
            
        } catch {
            print("Error fetching album tracks: \(error)")
            tracks = []
        }
        
        isLoadingTracks = false
    }
}
