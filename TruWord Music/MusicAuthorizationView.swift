//
//  MusicAuthorizationView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 3/22/26.
//
import UIKit
import SwiftUI

struct MusicAuthorizationView: View {
    var bottomPlayerHeight: CGFloat
    var hasPlayer: Bool

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Text("Please allow Apple Music to show Christian music")
                .multilineTextAlignment(.center)

            Button("Enable in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(.blue)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if hasPlayer {
                Color.clear.frame(height: bottomPlayerHeight)
            }
        }
    }
}

