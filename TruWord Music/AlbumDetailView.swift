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
    
    private let bottomPlayerHeight: CGFloat = 77
    
    var body: some View {
        Group {
            if isLoadingTracks {
                VStack {
                    Spacer()
                    ProgressView("Loading...")
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
                        VStack(spacing: 6) {
                            
                            if let artworkURL = album.artwork?.url(width: 1400, height: 1400) {
                                let screenWidth = UIScreen.main.bounds.width
                                let albumSize = min(max(screenWidth * 0.5, 150), 300)
                                
                                CustomAsyncImage(url: artworkURL)
                                    .frame(width: albumSize, height: albumSize)
                                    .clipped()
                                    .cornerRadius(12)
                            }
                            
                            Text(album.title)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                            
                            Text(album.artistName)
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.52))
                            
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 15)
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
                                
                                let currentAlbumWithTracks = AlbumWithTracks(album: album, tracks: tracks)
                                albumWithTracks = currentAlbumWithTracks
                                
                                playSong(song)
                                isPlayingFromAlbum = true
                                
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    
                                    Text(song.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .foregroundColor(
                                            isPlayable && networkMonitor.isConnected
                                            ? .primary
                                            : Color(UIColor.lightGray)
                                        )
                                    
                                    Text(song.artistName)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundColor(
                                            isPlayable && networkMonitor.isConnected
                                            ? Color(white: 0.48)
                                            : Color(UIColor.lightGray)
                                        )
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(!isPlayable || !networkMonitor.isConnected)
                        }
                    }
                    .listSectionSeparator(.visible, edges: .top)
                    
                    // MARK: - FOOTER (BOTTOM INFO)
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            
                            if let releaseDate = album.releaseDate {
                                Text("\(releaseDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote)
                                    .foregroundColor(Color(white: 0.52))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            if let album_copyright = album.copyright {
                                Text(album_copyright)
                                    .font(.footnote)
                                    .foregroundColor(Color(white: 0.52))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, album.releaseDate == nil ? 2 : 0)
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
            
            guard let fetchedAlbum = albumResponse.items.first else {
                tracks = []
                return
            }
            
            guard let albumTracks = fetchedAlbum.tracks, !albumTracks.isEmpty else {
                tracks = []
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
