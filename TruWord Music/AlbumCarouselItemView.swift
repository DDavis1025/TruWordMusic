import SwiftUI
import MusicKit

struct AlbumCarouselItemView: View {
    let album: Album

    var body: some View {
        let albumSize: CGFloat = 170

        VStack(spacing: 6) {

            if let artworkURL = album.artwork?.url(width: 280, height: 280) {
                CustomAsyncImage(url: artworkURL)
                    .frame(width: albumSize, height: albumSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(album.title)
                .font(.caption)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text(album.artistName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(width: albumSize)
    }
}
