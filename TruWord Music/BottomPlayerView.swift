import SwiftUI
import MusicKit
import FirebaseAnalytics

struct BottomPlayerView: View {
    let song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    let playerIsReady: Bool

    var body: some View {
        
        let songArtworkSize: CGFloat = 38
        let contentPadding: CGFloat = 10

        HStack(spacing: 12) {

            // MARK: - Artwork
            if let artworkURL = song.artwork?.url(width: 120, height: 120) {

                CustomAsyncImage(url: artworkURL)
                    .frame(width: songArtworkSize, height: songArtworkSize)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )
            }

            // MARK: - Info
            VStack(alignment: .leading, spacing: 2) {

                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(song.artistName)
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer()

            // MARK: - Play / Pause
            if playerIsReady {

                Button(action: {

                    togglePlayPause()

                    Analytics.logEvent(
                        "bottom_player_toggle",
                        parameters: [
                            "song_id": song.id.rawValue,
                            "action": isPlaying ? "pause" : "play"
                        ]
                    )

                }) {

                    Image(
                        systemName:
                            isPlaying
                            ? "pause.circle.fill"
                            : "play.circle.fill"
                    )
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                }

            } else {

                ProgressView()
                    .frame(width: 32, height: 32)
            }
        }

        // Equal padding on ALL sides
        .padding(contentPadding)

        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 0)

        .padding(.horizontal, 10)
        .padding(.bottom, 5)

        .onAppear {

            Analytics.logEvent(
                "bottom_player_shown",
                parameters: [
                    "song_id": song.id.rawValue
                ]
            )
        }
    }
}
