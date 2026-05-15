//
//  CustomAsyncImage.swift
//  TruWord Music
//
//  Created by Dillon Davis on 3/4/25.
//

import SwiftUI
import UIKit

// Create a global cache for images
class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    
    private init() {}
    
    func getImage(for url: URL) -> UIImage? {
        return cache.object(forKey: url as NSURL)
    }
    
    func setImage(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct CustomAsyncImage: View {
    let url: URL?
    
    @State private var image: UIImage? = nil
    @State private var isLoading: Bool = false
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill() // Fill the frame while maintaining aspect ratio
            } else if isLoading {
                ZStack {
                    Color(.secondarySystemBackground)
                        .cornerRadius(8)
                    ProgressView()
                }
            } else {
                // Directly use the "placeholder" image from assets
                Image(colorScheme == .dark ? "placeholder_dark" : "placeholder")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.6), lineWidth: 0.289)
        )
        .onAppear {
            loadImage()
            
        }
    }
    
    private func loadImage() {
        guard let url = url else { return }
        
        // Check if the image is already cached
        if let cachedImage = ImageCache.shared.getImage(for: url) {
            self.image = cachedImage
            return
        }
        
        isLoading = true
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let uiImage = UIImage(data: data) {
                // Cache the image
                ImageCache.shared.setImage(uiImage, for: url)
                
                DispatchQueue.main.async {
                    self.image = uiImage
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }.resume()
    }
}
