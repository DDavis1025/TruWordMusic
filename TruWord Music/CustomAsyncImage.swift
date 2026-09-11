import SwiftUI
import UIKit

class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 100
    }

    func getImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct CustomAsyncImage: View {
    let url: URL?
    let isCircle: Bool

    @State private var image: UIImage?
    @State private var isLoading = false

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()

            } else if isLoading {
                ZStack {
                    Color(.secondarySystemBackground)
                        .clipShape(
                            isCircle
                            ? AnyShape(Circle())
                            : AnyShape(RoundedRectangle(cornerRadius: 8))
                        )

                    ProgressView()
                }
            } else {
                Image(colorScheme == .dark ? "placeholder_dark" : "placeholder")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            isCircle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 8))
        )
        .overlay {
            if isCircle {
                Circle()
                    .stroke(Color.gray.opacity(0.6), lineWidth: 0.17)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.6), lineWidth: 0.17)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = url else { return }

        if let cachedImage = ImageCache.shared.getImage(for: url) {
            image = cachedImage
            return
        }

        guard !isLoading else { return }

        isLoading = true

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard
                let data = data,
                let uiImage = UIImage(data: data)
            else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }

            ImageCache.shared.setImage(uiImage, for: url)

            DispatchQueue.main.async {
                image = uiImage
                isLoading = false
            }
        }.resume()
    }
}
