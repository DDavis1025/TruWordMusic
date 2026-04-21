import SwiftUI
import MusicKit
import FirebaseAnalytics

struct BottomPlayerView: View {
    let song: Song
    @Binding var isPlaying: Bool
    let togglePlayPause: () -> Void
    let playerIsReady: Bool

    var body: some View {
        VStack(spacing: 0) {

            HStack {
                let screenWidth = UIScreen.main.bounds.width
                let songArtworkSize = min(max(screenWidth * 0.10, 30), 60)

                // Artwork
                if let artworkURL = song.artwork?.url(width: 120, height: 120) {
                    CustomAsyncImage(url: artworkURL)
                        .frame(width: songArtworkSize, height: songArtworkSize)
                        .clipped()
                        .cornerRadius(8)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(song.artistName)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.48))
                        .lineLimit(1)
                }

                Spacer()

                // MARK: - Play / Pause
                if playerIsReady {
                    Button(action: {
                        togglePlayPause()
                        Analytics.logEvent("bottom_player_toggle", parameters: [
                            "song_id": song.id.rawValue,
                            "action": isPlaying ? "pause" : "play"
                        ])
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                    .disabled(!playerIsReady)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal, 7)

        // 🔥 Track visibility
        .onAppear {
            Analytics.logEvent("bottom_player_shown", parameters: [
                "song_id": song.id.rawValue
            ])
        }
    }
}
