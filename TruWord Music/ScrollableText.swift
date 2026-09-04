//
//  ScrollableText.swift
//  TruWord Music
//

import SwiftUI
import MusicKit
import UIKit

struct ScrollableText: View {
    let text: String
    @Binding var isAnimating: Bool
    let scrollSpeed: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    @State private var animationController: MarqueeAnimationController?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Hidden text used to measure the full width.
                Text(text)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear
                                .onAppear {
                                    updateMeasurements(
                                        textWidth: textGeometry.size.width,
                                        containerWidth: geometry.size.width
                                    )
                                }
                                .onChange(of: text) {
                                    updateMeasurements(
                                        textWidth: textGeometry.size.width,
                                        containerWidth: geometry.size.width
                                    )
                                }
                        }
                    )
                    .hidden()

                // Visible text.
                Text(text)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
            }
        }
        .frame(height: 25)
        .clipped()
        .onTapGesture {
            startScrolling()
        }
        .onAppear {
            setupAnimationController()
        }
        .onDisappear {
            stopScrolling()
        }
        .onChange(of: text) {
            stopScrolling()

            // Reset position when the song changes.
            offset = 0

            setupAnimationController()
        }
    }

    // MARK: - Measurements

    private func updateMeasurements(
        textWidth: CGFloat,
        containerWidth: CGFloat
    ) {
        self.textWidth = textWidth
        self.containerWidth = containerWidth

        animationController?.textWidth = textWidth
        animationController?.containerWidth = containerWidth
        animationController?.scrollSpeed = scrollSpeed
    }

    // MARK: - Animation Setup

    private func setupAnimationController() {
        if animationController == nil {
            let controller = MarqueeAnimationController()

            controller.onUpdate = { newOffset in
                offset = newOffset
            }

            controller.onFinished = {
                isAnimating = false
                offset = 0
            }

            animationController = controller
        }

        animationController?.textWidth = textWidth
        animationController?.containerWidth = containerWidth
        animationController?.scrollSpeed = scrollSpeed
    }

    // MARK: - Start / Stop

    private func startScrolling() {
        guard textWidth > containerWidth else {
            return
        }

        guard !isAnimating else {
            return
        }

        setupAnimationController()

        isAnimating = true

        animationController?.start()
    }

    private func stopScrolling() {
        animationController?.stop()

        offset = 0
        isAnimating = false
    }

    // MARK: - Reset

    func resetPhase() {
        stopScrolling()
    }
}


// MARK: - CADisplayLink Animation Controller

@MainActor
final class MarqueeAnimationController: NSObject {

    var textWidth: CGFloat = 0
    var containerWidth: CGFloat = 0
    var scrollSpeed: CGFloat = 47.0

    var onUpdate: ((CGFloat) -> Void)?
    var onFinished: (() -> Void)?

    private var displayLink: CADisplayLink?

    private var startTime: CFTimeInterval = 0
    private var pauseStartTime: CFTimeInterval = 0

    private var state: AnimationState = .idle

    private enum AnimationState {
        case idle
        case scrollingLeft
        case paused
        case scrollingRight
    }

    private var distance: CGFloat {
        max(textWidth - containerWidth, 0)
    }

    private var scrollDuration: CFTimeInterval {
        guard scrollSpeed > 0 else {
            return 0
        }

        return CFTimeInterval(distance / scrollSpeed)
    }

    // MARK: - Start

    func start() {
        stop()

        guard distance > 0 else {
            return
        }

        state = .scrollingLeft

        startTime = CACurrentMediaTime()

        let link = CADisplayLink(
            target: self,
            selector: #selector(displayLinkTick)
        )

        link.add(
            to: .main,
            forMode: .common
        )

        displayLink = link
    }

    // MARK: - Stop

    func stop() {
        displayLink?.invalidate()
        displayLink = nil

        state = .idle
        startTime = 0
        pauseStartTime = 0
    }

    // MARK: - Display Update

    @objc
    private func displayLinkTick(_ displayLink: CADisplayLink) {
        let currentTime = CACurrentMediaTime()

        switch state {

        // --------------------------------
        // Scroll left
        // --------------------------------

        case .scrollingLeft:

            let elapsed = currentTime - startTime

            guard scrollDuration > 0 else {
                finish()
                return
            }

            let progress = min(
                elapsed / scrollDuration,
                1.0
            )

            let newOffset = -distance * CGFloat(progress)

            onUpdate?(newOffset)

            if progress >= 1.0 {
                state = .paused
                pauseStartTime = currentTime

                // Make absolutely sure we land exactly
                // at the end position.
                onUpdate?(-distance)
            }

        // --------------------------------
        // Pause for 3 seconds
        // --------------------------------

        case .paused:

            let elapsed = currentTime - pauseStartTime

            onUpdate?(-distance)

            if elapsed >= 3.0 {
                state = .scrollingRight
                startTime = currentTime
            }

        // --------------------------------
        // Scroll right
        // --------------------------------

        case .scrollingRight:

            let elapsed = currentTime - startTime

            guard scrollDuration > 0 else {
                finish()
                return
            }

            let progress = min(
                elapsed / scrollDuration,
                1.0
            )

            let newOffset =
                -distance +
                (distance * CGFloat(progress))

            onUpdate?(newOffset)

            if progress >= 1.0 {
                finish()
            }

        case .idle:
            break
        }
    }

    // MARK: - Finish

    private func finish() {
        state = .idle

        onUpdate?(0)

        displayLink?.invalidate()
        displayLink = nil

        onFinished?()
    }

    deinit {
        displayLink?.invalidate()
    }
}
