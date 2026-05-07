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
                        .fontWeight(.regular)
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
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.955)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 10)
        .padding(.bottom, 5)

        // 🔥 Track visibility
        .onAppear {
            Analytics.logEvent("bottom_player_shown", parameters: [
                "song_id": song.id.rawValue
            ])
        }
    }
}
