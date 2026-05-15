import Combine
import SwiftUI
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        willChange
            .merge(with: willHide)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handle(notification)
            }
            .store(in: &cancellables)
    }

    private func handle(_ notification: Notification) {
        guard notification.name != UIResponder.keyboardWillHideNotification,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            height = 0
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        height = max(0, screenHeight - frame.minY)
    }
}

private struct KeyboardAdaptivePaddingModifier: ViewModifier {
    @StateObject private var keyboard = KeyboardObserver()
    var extra: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboard.height > 0 ? keyboard.height + extra : 0)
            .animation(.easeOut(duration: 0.22), value: keyboard.height)
    }
}

extension View {
    func keyboardAdaptivePadding(extra: CGFloat = 12) -> some View {
        modifier(KeyboardAdaptivePaddingModifier(extra: extra))
    }
}
