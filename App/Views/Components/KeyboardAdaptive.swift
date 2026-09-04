import Combine
import SwiftUI
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0
    @Published private(set) var animationDuration: TimeInterval = 0.25

    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in self?.handle(notification) }
            .store(in: &cancellables)
    }

    private func handle(_ notification: Notification) {
        if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval {
            animationDuration = duration
        }
        guard notification.name != UIResponder.keyboardWillHideNotification,
              let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) else {
            height = 0
            return
        }

        let frameInWindow = window.convert(keyboardFrame, from: nil)
        height = max(0, window.bounds.maxY - frameInWindow.minY)
    }
}

private struct KeyboardAdaptivePaddingModifier: ViewModifier {
    var extra: CGFloat

    func body(content: Content) -> some View {
        content
            // SwiftUI'nin keyboard safe-area daraltmasını kullan. Ekran koordinatından
            // elle klavye yüksekliği çıkarmak sheet ve Display Zoom altında iki kez inset
            // uygulanmasına yol açıyordu.
            .padding(.bottom, extra)
    }
}

extension View {
    func keyboardAdaptivePadding(extra: CGFloat = 12) -> some View {
        modifier(KeyboardAdaptivePaddingModifier(extra: extra))
    }
}
