import SwiftUI
import MusicKit
import FirebaseAnalytics

struct FullAlbumGridView: View {
    let albums: [Album]
    let onAlbumSelected: (Album) -> Void
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager

    @State private var searchQuery: String = ""

    private let bottomPlayerHeight: CGFloat = 70

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
        VStack(spacing: 0) {

            // MARK: - OFFLINE STATE
            if !networkMonitor.isConnected {
                VStack(spacing: 10) {
                    Spacer()

                    Text("No Internet connection")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("Your device is not connected to the internet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // MARK: - GRID CONTENT
            else {
                GeometryReader { proxy in

                    let spacing: CGFloat = 20
    
                    // Adaptive columns based on available width
                    let columnsCount = max(Int(proxy.size.width / 180), 2)

                    let columns = Array(
                        repeating: GridItem(.flexible(), spacing: spacing),
                        count: columnsCount
                    )

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: spacing) {

                            ForEach(filteredAlbums, id: \.id) { album in

                                VStack(spacing: 6) {

                                    if let artworkURL = album.artwork?.url(width: 280, height: 280) {
                                        CustomAsyncImage(url: artworkURL)
                                            .frame(height: 170)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    Text(album.title)
                                        .font(.caption)
                                        .lineLimit(1)

                                    Text(album.artistName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .onTapGesture {

                                    Analytics.logEvent("album_selected_from_grid", parameters: [
                                        "album_id": album.id.rawValue,
                                        "album_title": album.title,
                                        "artist_name": album.artistName
                                    ])

                                    onAlbumSelected(album)
                                }
                            }
                        }
                        .padding()
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            }
        }

        // MARK: - NAVIGATION
        .navigationTitle("Top Albums")
        .navigationBarTitleDisplayMode(.inline)

        // MARK: - ANALYTICS
        .onAppear {
            Analytics.logEvent("album_grid_viewed", parameters: [
                "album_count": filteredAlbums.count
            ])
        }

        .onChange(of: searchQuery) { _, newValue in
            guard !newValue.isEmpty else { return }

            Analytics.logEvent("album_grid_searched", parameters: [
                "query": newValue
            ])
        }

        // MARK: - SEARCH
        .if(networkMonitor.isConnected) { view in
            view.searchable(text: $searchQuery)
        }
    }
}
