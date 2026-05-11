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
        Group {
            if isLoadingTracks {
                VStack {
                    Spacer()
                    ProgressView("Loading tracks...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
                
            } else if tracks.isEmpty {
                Text("No tracks available")
                    .padding()
                
            } else {
                
                List {
                    // MARK: - HEADER
                    Section {
                        VStack(spacing: 12) {
                            
                            if let artworkURL = album.artwork?.url(width: 1400, height: 1400) {
                                
                                CustomAsyncImage(url: artworkURL)
                                    .frame(width: 240, height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            
                            VStack(spacing: 4) {
                                Text(album.title)
                                    .font(.headline)
                                    .multilineTextAlignment(.center)
                                
                                Text(album.artistName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    
                    // MARK: - TRACK LIST
                    Section {
                        ForEach(tracks, id: \.id) { song in
                            
                            let isPlayable =
                            (song.releaseDate == nil || song.releaseDate! <= Date()) &&
                            song.playParameters != nil
                            
                            Button {
                                guard isPlayable && networkMonitor.isConnected else { return }
                                
                                Analytics.logEvent("album_song_selected", parameters: [
                                    "song_id": song.id.rawValue,
                                    "album_id": album.id.rawValue
                                ])
                                
                                albumWithTracks = AlbumWithTracks(album: album, tracks: tracks)
                                
                                playSong(song)
                                isPlayingFromAlbum = true
                                
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    
                                    Text(song.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .foregroundStyle(
                                            isPlayable && networkMonitor.isConnected
                                            ? .primary
                                            : .secondary
                                        )
                                    
                                    Text(song.artistName)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(!isPlayable || !networkMonitor.isConnected)
                        }
                    }
                    
                    // MARK: - FOOTER
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            
                            if let releaseDate = album.releaseDate {
                                Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let album_copyright = album.copyright {
                                Text(album_copyright)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 30, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        
        // MARK: - Analytics
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
    
    // MARK: - Helpers
    
    func setSelectedAlbum(album: Album) async {
        playerManager.selectedAlbum = album
    }
    
    func fetchAlbumTracks(album: Album) async {
        do {
            var albumRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: album.id)
            albumRequest.properties = [.tracks]
            
            let albumResponse = try await albumRequest.response()
            
            guard let fetchedAlbum = albumResponse.items.first,
                  let albumTracks = fetchedAlbum.tracks,
                  !albumTracks.isEmpty else {
                tracks = []
                isLoadingTracks = false
                return
            }
            
            let trackIDs = albumTracks.compactMap { $0.id }
            
            let songsRequest = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: trackIDs)
            let songResponse = try await songsRequest.response()
            
            tracks = Array(songResponse.items)
            
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
