import SwiftUI
import MusicKit
import FirebaseAnalytics

struct AlbumDetailView: View {
    let album: Album
    let playSong: (Song) -> Void
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumWithTracks: AlbumWithTracks?
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    private let bottomPlayerHeight: CGFloat = 77
    
    private var appleMusicURL: URL? {
        URL(string: "https://music.apple.com/us/album/\(album.id)")
    }
    
    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
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
                                
                                CustomAsyncImage(url: artworkURL, isCircle: false)
                                    .frame(width: albumSize, height: albumSize)
                            }
                            
                            Text(album.title)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                            
                            Text(album.artistName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let appleMusicURL, !playerManager.appleMusicSubscription {
                                
                                HStack {
                                    Spacer()
                                    
                                    Image("AppleMusicBadge")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: min(UIScreen.main.bounds.width * 0.1, 65))
                                        .padding(.top, 12)
                                        .onTapGesture {
                                            Analytics.logEvent("apple_music_album_link_tapped", parameters: [
                                                "album_id": album.id.rawValue
                                            ])
                                            UIApplication.shared.open(appleMusicURL)
                                        }
                                    
                                    Spacer()
                                }
                            }
                            
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
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            if let album_copyright = album.copyright {
                                Text(album_copyright)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
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
        .navigationBarTitleDisplayMode(.inline)
        
        .task(id: album.id) {
            isLoading = true
            tracks = []

            let fetchedTracks = await fetchAlbumTracks(album: album)

            await MainActor.run {
                self.tracks = fetchedTracks
                self.isLoading = false
            }
        }
        
        .onAppear {
            Analytics.logEvent("album_viewed", parameters: [
                "album_id": album.id.rawValue,
                "album_title": album.title,
                "artist_name": album.artistName
            ])
        }
    }
    
    // MARK: - Helpers
    
    func setSelectedAlbum(album: Album) async {
        playerManager.selectedAlbum = album
    }
    
    func fetchAlbumTracks(album: Album) async -> [Song] {
        do {
            var albumRequest = MusicCatalogResourceRequest<Album>(
                matching: \.id,
                equalTo: album.id
            )

            albumRequest.properties = [.tracks]

            let albumResponse = try await albumRequest.response()

            guard let fetchedAlbum = albumResponse.items.first,
                  let albumTracks = fetchedAlbum.tracks else {
                return []
            }

            let trackIDs = albumTracks.compactMap { $0.id }

            let songsRequest = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                memberOf: trackIDs
            )

            let songResponse = try await songsRequest.response()

            return Array(songResponse.items)

        } catch {
            print("Error fetching album tracks: \(error)")
            return []
        }
    }
}
