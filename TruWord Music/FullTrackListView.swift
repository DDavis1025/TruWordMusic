import SwiftUI
import MusicKit
import FirebaseAnalytics

struct FullTrackListView: View {
    let songs: [Song]
    let playSong: (Song) -> Void
    @Binding var currentPlayingSong: Song?
    @Binding var isPlayingFromAlbum: Bool
    
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var playerManager: PlayerManager
    
    @State private var searchQuery: String = ""

    private let bottomPlayerHeight: CGFloat = 77

    var filteredSongs: [Song] {
        if searchQuery.isEmpty {
            return songs
        } else {
            return songs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchQuery) ||
                song.artistName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    var body: some View {
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
            else if filteredSongs.isEmpty {
                Spacer()

                Text("No tracks found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()
            }

            // MARK: - CONTENT
            else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredSongs, id: \.id) { song in
                            SongRowView(
                                song: song,
                                currentPlayingSong: $currentPlayingSong,
                                leftPadding: 8,
                                rightPadding: 8
                            )
                            .onTapGesture {
                                UIApplication.shared.dismissKeyboard()

                                // 🔥 Track song selection
                                Analytics.logEvent("track_selected_from_list", parameters: [
                                    "song_id": song.id.rawValue,
                                    "song_title": song.title,
                                    "artist_name": song.artistName
                                ])

                                playSong(song)
                                isPlayingFromAlbum = false
                            }
                            .padding(.vertical, 4)
                            .background(Color(.systemBackground))
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if playerManager.currentlyPlayingSong != nil {
                        Color.clear.frame(height: bottomPlayerHeight)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle("Top Songs")
        .navigationBarTitleDisplayMode(.inline)

        // 🔥 Track view appearance
        .onAppear {
            Analytics.logEvent("track_list_viewed", parameters: [
                "track_count": filteredSongs.count
            ])
        }

        // 🔥 Track search behavior
        .onChange(of: searchQuery) { _, newValue in
            guard !newValue.isEmpty else { return }

            Analytics.logEvent("track_list_searched", parameters: [
                "query": newValue
            ])
        }

        .if(networkMonitor.isConnected) { view in
            view.searchable(text: $searchQuery)
        }
    }
}

extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
