//
//  FullVerseView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 4/29/26.
//

import SwiftUI

struct FullVerseView: View {
    let verse: Verse
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // Drag indicator space (makes it feel like a sheet)
                Capsule()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Header
                        HStack(spacing: 6) {
                            Image(systemName: "book")
                                .foregroundColor(.gray)

                            Text("Verse of the Day")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }

                        // Verse Text (LEFT ALIGNED ✅)
                        Text(verse.text)
                            .font(.system(.title2, design: .serif))
                            .multilineTextAlignment(.leading)

                        // Reference
                        Text(verse.reference)
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                // Close Button (centered like you wanted)
                Button(action: {
                    dismiss()
                }) {
                    Text("Close")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}
