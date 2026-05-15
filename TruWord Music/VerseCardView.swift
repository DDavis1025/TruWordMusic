//
//  VerseCardView.swift
//  TruWord Music
//
//  Created by Dillon Davis on 4/29/26.
//

import SwiftUI
import FirebaseAnalytics

struct VerseCardView: View {
    let verse: Verse?
    @State private var showFullVerse = false
    
    var body: some View {
        if let verse = verse {
            Button {
                showFullVerse = true
                
                Analytics.logEvent("daily_verse_expanded", parameters: [
                    "reference": verse.reference
                ])
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    
                    HStack(spacing: 4) {  // Default is around 8
                        Image(systemName: "book")
                        Text("Verse of the Day")
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)  // Between caption and subheadline
                    
                    Text("“\(verse.text)”")
                        .font(.system(.body, design: .serif))
                        .lineLimit(2) // ✅ truncate to 2 lines
                        .truncationMode(.tail)
                    
                    Text(verse.reference)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            
            // ✅ Pretty Expanded View
            .sheet(isPresented: $showFullVerse) {
                FullVerseView(verse: verse)
                    .presentationDetents([.medium, .large]) // ✅ works now
                    .presentationDragIndicator(.hidden) // optional (we added our own)
            }
        }
    }
}
