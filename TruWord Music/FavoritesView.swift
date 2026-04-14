import SwiftUI
import MusicKit

struct FavoritesView: View {
    @EnvironmentObject var favoritesManager: FavoritesManager

    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager

    @Binding var navigationPath: NavigationPath
    @Binding var currentPlayingSong: Song?
    @Binding var isPlayingFromAlbum: Bool
    
    @Binding var musicAuthorized: Bool

    @State private var searchQuery: String = ""

    private let bottomPlayerHeight: CGFloat = 70

    var filteredSongs: [Song] {
        if searchQuery.isEmpty {
            return favoritesManager.favoriteSongs
        } else {
            return favoritesManager.favoriteSongs.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.artistName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {

                // MARK: - No Internet
                if !networkMonitor.isConnected {
                    noInternetView

                // MARK: - Empty State
                } else if !musicAuthorized {
                    MusicAuthorizationView(
                        bottomPlayerHeight: bottomPlayerHeight,
                        hasPlayer: playerManager.currentlyPlayingSong != nil
                    )
                    .padding(.horizontal, 16)
                } else if favoritesManager.favoriteSongs.isEmpty {
                    emptyStateView

                // MARK: - Content
                } else {
                    contentView
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)

            // ONLY show search when online
            .if(networkMonitor.isConnected && musicAuthorized) { view in
                view.searchable(text: $searchQuery, prompt: "Search Favorites")
            }

            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(
                    album: album,
                    playSong: { song in
                        let songsFromFavorites = favoritesManager.favoriteSongs

                        playerManager.playSong(
                            song,
                            from: songsFromFavorites,
                            albumWithTracks: playerManager.albumWithTracks,
                            playFromAlbum: true,
                            networkMonitor: networkMonitor
                        )
                    },
                    isPlayingFromAlbum: $playerManager.isPlayingFromAlbum,
                    albumWithTracks: $playerManager.albumWithTracks,
                    networkMonitor: networkMonitor,
                    playerManager: playerManager
                )
            }
        }
        .task {
            await favoritesManager.fetchFavoriteSongs()
        }
    }

    // MARK: - CONTENT VIEW
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {

                ForEach(filteredSongs, id: \.id) { song in
                    HStack(spacing: 6) {

                        SongRowView(
                            song: song,
                            currentPlayingSong: $currentPlayingSong,
                            leftPadding: 8,
                            rightPadding: 0
                        )

                        Button {
                            withAnimation {
                                favoritesManager.toggleFavorite(song)
                            }
                        } label: {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .padding(.trailing, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.dismissKeyboard()
                        playerManager.playSong(song, from: favoritesManager.favoriteSongs)
                        isPlayingFromAlbum = false
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }

    // MARK: - EMPTY STATE
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundColor(.gray)

            Text("No Favorites Yet")
                .font(.headline)

            Text("Tap the star on any song to save it here")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }

    // MARK: - NO INTERNET VIEW
    private var noInternetView: some View {
        VStack(spacing: 8) {
            Spacer()

            Text("No Internet connection")
                .font(.headline)

            Text("Your device is not connected to the internet")
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentlyPlayingSong != nil {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }
}
