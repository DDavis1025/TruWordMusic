//
//  ScrollableText.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/7/25.
//

import SwiftUI
import MusicKit

struct ScrollableText: View {
    let text: String
    @Binding var isAnimating: Bool
    let scrollSpeed: CGFloat
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var phase: AnimationPhase = .idle
    
    enum AnimationPhase {
        case idle
        case scrollingLeft
        case paused
        case scrollingRight
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Measure text width
                Text(text)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(GeometryReader { textGeometry in
                        Color.clear
                            .onAppear {
                                updateWidths(textGeometry: textGeometry, containerWidth: geometry.size.width)
                            }
                            .onChange(of: text) {
                                updateWidths(textGeometry: textGeometry, containerWidth: geometry.size.width)
                            }
                    })
                    .hidden() // Hide measuring text
                
                // Visible scrolling text
                Text(text)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: calculateOffset())
                    .animation(.linear(duration: calculateDuration()), value: phase) // Use calculated duration
                    .onChange(of: phase) { _, _ in handleAnimationState() }
            }
        }
        .frame(height: 25) // Constrain height to avoid excessive spacing
        .clipped()
        .onTapGesture {
            if textWidth > containerWidth && !isAnimating {
                isAnimating = true
                phase = .scrollingLeft
            }
        }
    }
    
    private func updateWidths(textGeometry: GeometryProxy, containerWidth: CGFloat) {
        textWidth = textGeometry.size.width
        self.containerWidth = containerWidth
    }
    
    private func calculateOffset() -> CGFloat {
        switch phase {
        case .idle:
            return 0
        case .scrollingLeft:
            return -textWidth + containerWidth
        case .paused:
            return -textWidth + containerWidth
        case .scrollingRight:
            return 0
        }
    }
    
    private func calculateDuration() -> Double {
        let distance = textWidth - containerWidth
        return Double(distance / scrollSpeed)
    }
    
    private func handleAnimationState() {
        switch phase {
        case .scrollingLeft:
            DispatchQueue.main.asyncAfter(deadline: .now() + calculateDuration()) { phase = .paused }
        case .paused:
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { phase = .scrollingRight }
        case .scrollingRight:
            DispatchQueue.main.asyncAfter(deadline: .now() + calculateDuration()) {
                phase = .idle
                isAnimating = false
            }
        case .idle:
            break
        }
    }
    
    // Method to reset the phase
    func resetPhase() {
        phase = .idle
    }
}

