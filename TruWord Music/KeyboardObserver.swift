//
//  KeyboardObserver.swift
//  TruWord Music
//
//  Created by Dillon Davis on 9/9/25.
//

import SwiftUI
import Combine

class KeyboardObserver: ObservableObject {
    @Published var isKeyboardVisible: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.isKeyboardVisible = true }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.isKeyboardVisible = false }
            .store(in: &cancellables)
    }
}


