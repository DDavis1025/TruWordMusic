import SwiftUI
import MusicKit
import FirebaseAnalytics

struct AlbumDetailView: View {
    let album: Album
    let playSong: (Song) -> Void
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    @State private var isArtistPressed = false
    @State private var relatedAlbums: [Album] = []
    @State private var resolvedAlbum: Album?
    @State private var moreByArtist: Artist?
    @State private var moreByAlbums: [Album] = []
    @Binding var isPlayingFromAlbum: Bool
    @Binding var albumWithTracks: AlbumWithTracks?
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    @Binding var navigationPath: [Route]
    @Binding var albumCache: [MusicItemID: Album]
    
    private let bottomPlayerHeight: CGFloat = 77
  
    private var appleMusicURL: URL? {
        AppleMusicAffiliateManager.makeURL(type: .album, id: album.id)
    }
    
    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    ProgressView("Loading...")
                }
                .padding(.bottom, playerManager.currentlyPlayingSong != nil ? bottomPlayerHeight : 0)
                
            } else if !networkMonitor.isConnected {
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
            } else if tracks.isEmpty {
                VStack {
                    Spacer()
                    
                    Text("No tracks available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.bottom, playerManager.currentlyPlayingSong != nil ? bottomPlayerHeight : 0)
            } else {
                List {
                    
                    // MARK: - HEADER
                    Section {
                        VStack(spacing: 8) {
                            
                            let artworkURL = album.artwork?.url(width: 1400, height: 1400)
                            let screenWidth = UIScreen.main.bounds.width
                            let albumSize = min(max(screenWidth * 0.5, 150), 300)
                            
                            CustomAsyncImage(url: artworkURL, isCircle: false)
                                .frame(width: albumSize, height: albumSize)
                            
                            
                            Text(album.title)
                                .font(.system(size: 20, weight: .bold))
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                                .padding(.horizontal, 10)
                            
                            Button {
                                isArtistPressed = true

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isArtistPressed = false
                                }

                                Analytics.logEvent("artist_from_album_tapped", parameters: [
                                    "artist_name": album.artistName,
                                    "album_id": album.id.rawValue
                                ])

                                Task {
                                    await openArtistFromAlbum()
                                }
                            } label: {
                                Text(album.artistName)
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundColor(isArtistPressed ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal, 10)
                                    .multilineTextAlignment(.center)
                                    .animation(.easeOut(duration: 0.1), value: isArtistPressed)
                            }
                            .buttonStyle(.plain)
                            
                            if let appleMusicURL, !playerManager.appleMusicSubscription {
                                
                                HStack {
                                    Spacer()
                                    
                                    Image("AppleMusicBadge")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: min(UIScreen.main.bounds.width * 0.1, 65))
                                        .padding(.top, 20.2)
                                        .onTapGesture {
                                            Analytics.logEvent("apple_music_link_tapped", parameters: [
                                                "source": "album_detail",
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
                                guard isPlayable else { return }
                                
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
                                            isPlayable
                                            ? .primary
                                            : Color(UIColor.lightGray)
                                        )
                                    
                                    Text(song.artistName)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundColor(
                                            isPlayable
                                            ? Color(white: 0.48)
                                            : Color(UIColor.lightGray)
                                        )
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(!isPlayable)
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
                    // MARK: - RELATED ALBUMS
                    if !relatedAlbums.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {

                                HStack {
                                    Text("Related Albums")
                                        .font(.system(size: 20, weight: .bold))
                                    Spacer()
                                }
                                .padding(.leading, 10)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {

                                        ForEach(relatedAlbums, id: \.id) { album in
                                            AlbumCarouselItemView(album: album)
                                                .onTapGesture {
                                                    albumCache[album.id] = album   // 🔥 ADD THIS

                                                    navigationPath.append(.album(album.id))

                                                    Analytics.logEvent("related_album_opened", parameters: [
                                                        "album_id": album.id.rawValue,
                                                        "album_title": album.title
                                                    ])
                                                }
                                        }
                                    }
                                    .padding(.leading, 8)
                                    .padding(.trailing, 16)
                                }
                            }
                            .padding(.bottom, 20)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    }
                    if let artist = moreByArtist,
                       !moreByAlbums.isEmpty {

                        Section {

                            VStack(alignment: .leading, spacing: 12) {
                                
                                HStack(spacing: 4) {

                                    Text("More By \(artist.name)")
                                        .font(.system(size: 20, weight: .bold))
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    if moreByAlbums.count > 10 {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.gray)
                                    }

                                    Spacer()
                                }
                                .padding(.leading, 10)
                                .padding(.trailing, 5)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    navigationPath.append(
                                        .artistAlbumGrid(
                                            title: artist.name,
                                            albums: moreByAlbums,
                                            showAlbumYear: true,
                                            source: "more_by_artist"
                                            
                                        )
                                    )
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {

                                        ForEach(moreByAlbums.prefix(10), id: \.id) { album in
                                            AlbumCarouselItemView(album: album, showAlbumYear: true)
                                                .onTapGesture {
                                                    albumCache[album.id] = album
                                                    navigationPath.append(.album(album.id))
                                                    
                                                    Analytics.logEvent("more_by_album_opened", parameters: [
                                                        "album_id": album.id.rawValue,
                                                        "album_title": album.title,
                                                        "artist_id": artist.id.rawValue,
                                                        "artist_name": artist.name
                                                    ])
                                                }
                                        }
                                    }
                                    .padding(.leading, 8)
                                    .padding(.trailing, 16)
                                }
                            }
                            .padding(.bottom, 20)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
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
        .toolbar {
            if networkMonitor.isConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: appleMusicURL ?? URL(string: "https://apps.apple.com/app/id6744539952")!
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .onTapGesture {
                        Analytics.logEvent("share_sheet_opened", parameters: [
                            "album_id": album.id.rawValue,
                            "artist_name": album.artistName,
                            "source": "album_detail"
                        ])
                    }
                }
            }
        }
        
        .task(id: album.id) {
            isLoading = true
            tracks = []

            async let fetchedTracks = fetchAlbumTracks(album: album)
            async let fetchedRelated = fetchRelatedAlbums()
            async let fetchedMoreBy = fetchMoreByArtist()

            let (tracksResult, _, _) = await (
                fetchedTracks,
                fetchedRelated,
                fetchedMoreBy
            )

            await MainActor.run {
                self.tracks = tracksResult
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
    
    private func fetchRelatedAlbums() async {
        do {
            var request = MusicCatalogResourceRequest<Album>(
                matching: \.id,
                equalTo: album.id
            )

            request.properties = [.relatedAlbums]
            request.limit = 1

            let response = try await request.response()

            guard let fullAlbum = response.items.first,
                  let albums = fullAlbum.relatedAlbums else {
                return
            }

            let filtered = albums.filter { album in
                let isChristian =
                    album.genreNames.contains("Christian") ||
                    album.genreNames.contains("Christian & Gospel")

                let isNotExplicit = album.contentRating != .explicit

                return isChristian && isNotExplicit
            }

            await MainActor.run {
                self.relatedAlbums = filtered
            }

        } catch {
            print("Error fetching related albums: \(error)")
        }
    }
    
    private func fetchPreferredArtistFromAlbum() async throws -> Artist {
        var request = MusicCatalogResourceRequest<Album>(
            matching: \.id,
            equalTo: album.id
        )

        request.properties = [.artists]

        let response = try await request.response()

        guard let fullAlbum = response.items.first,
              let artists = fullAlbum.artists,
              let firstArtist = artists.first else {
            throw URLError(.badServerResponse)
        }

        for artist in artists {
            if try await artistHasChristianContent(artist) {
                return artist
            }
        }

        // Fallback to the first artist if none are Christian
        return firstArtist
    }
    
    private func artistHasChristianContent(_ artist: Artist) async throws -> Bool {
        var request = MusicCatalogResourceRequest<Artist>(
            matching: \.id,
            equalTo: artist.id
        )

        request.properties = [.albums, .topSongs]
        request.limit = 1

        let response = try await request.response()

        guard let fullArtist = response.items.first else {
            return false
        }

        let hasChristianAlbum = fullArtist.albums?.contains { album in
            album.genreNames.contains("Christian") ||
            album.genreNames.contains("Christian & Gospel") &&
            album.contentRating != .explicit
        } ?? false
        
        let hasChristianSong = fullArtist.topSongs?.contains { song in
            song.genreNames.contains("Christian") ||
            song.genreNames.contains("Christian & Gospel") &&
            song.contentRating != .explicit
        } ?? false

        return hasChristianAlbum || hasChristianSong
    }
    
    
    private func openArtistFromAlbum() async {
        do {
            let artist = try await fetchPreferredArtistFromAlbum()

            await MainActor.run {
                navigationPath.append(.artist(artist.id))
            }

        } catch {
            print("Failed to open artist: \(error)")
        }
    }
    
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
    
    private func fetchMoreByArtist() async {
        do {
            let artist = try await fetchPreferredArtistFromAlbum()

            var request = MusicCatalogResourceRequest<Artist>(
                matching: \.id,
                equalTo: artist.id
            )

            request.properties = [.albums]
            request.limit = 1

            let response = try await request.response()

            guard let fullArtist = response.items.first else { return }

            let filtered = Array(fullArtist.albums ?? []).filter { album in
                let isChristian =
                    album.genreNames.contains("Christian") ||
                    album.genreNames.contains("Christian & Gospel")

                let isNotExplicit = album.contentRating != .explicit

                let isNotCurrentAlbum = album.id != self.album.id

                return isChristian && isNotExplicit && isNotCurrentAlbum
            }

            await MainActor.run {
                self.moreByArtist = artist
                self.moreByAlbums = filtered
            }

        } catch {
            print(error)
        }
    }
}
