//
//  CustomAsyncImage.swift
//  TruWord Music
//
//  Created by Dillon Davis on 3/4/25.
//

import SwiftUI

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
        isLoading = true
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let uiImage = UIImage(data: data) {
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

