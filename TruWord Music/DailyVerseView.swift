//
//  DailyVerseView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 3/16/26.
//

import SwiftUI
import FirebaseAnalytics

struct DailyVerseView: View {
    @ObservedObject var manager: DailyVerseManager
    @State private var showFullVerse = false

    var body: some View {
        if let verse = manager.verse {

            VStack(alignment: .leading, spacing: 8) {

                // MARK: - Title + Refresh
                HStack {
                    Text("Verse of the Day")
                        .font(.system(size: 18)).bold()
                        .foregroundColor(.black)

                    Spacer()

                    Button(action: {
                        Analytics.logEvent("daily_verse_refresh_tapped", parameters: [
                            "reference": verse.reference
                        ])

                        manager.refreshIfNewDay()
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - Verse Card
                Button(action: {
                    Analytics.logEvent("daily_verse_expanded", parameters: [
                        "reference": verse.reference
                    ])

                    showFullVerse.toggle()
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verse.reference)
                            .font(.subheadline)
                            .foregroundColor(.black)

                        Text(verse.text)
                            .font(.body)
                            .foregroundColor(.black)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 4)
                }

                // MARK: - Full Verse Sheet
                .sheet(isPresented: $showFullVerse) {
                    VStack(spacing: 16) {

                        Text(verse.reference)
                            .font(.title2)
                            .bold()

                        ScrollView {
                            Text(verse.text)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .padding()
                        }

                        Button("Close") {
                            showFullVerse = false

                            Analytics.logEvent("daily_verse_closed", parameters: [
                                "reference": verse.reference
                            ])
                        }
                        .padding()
                        .foregroundColor(.blue)
                    }
                    .padding()
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 14)

            // MARK: - Impression Tracking (important)
            .onAppear {
                Analytics.logEvent("daily_verse_viewed", parameters: [
                    "reference": verse.reference
                ])
            }
        }
    }
}
