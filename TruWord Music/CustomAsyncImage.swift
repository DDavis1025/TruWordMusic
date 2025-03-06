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
    let placeholder: Image
    
    @State private var image: UIImage? = nil
    @State private var isLoading: Bool = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView() // Show a loading indicator
                    .frame(width: 50, height: 50)
            } else {
                placeholder // Show a placeholder if the image fails to load
            }
        }
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
