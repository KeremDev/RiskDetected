import SwiftUI
import UIKit

/// One non-consuming recognizer per application window covers pages and presented forms.
/// It stays with the window when a full-screen presentation detaches the root view.
struct RDKeyboardDismissBehavior: UIViewRepresentable {
    func makeUIView(context: Context) -> Installer { Installer() }
    func updateUIView(_ uiView: Installer, context: Context) { uiView.installIfNeeded() }

    final class Installer: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            installIfNeeded()
        }
        func installIfNeeded() {
            guard let window,
                  !(window.gestureRecognizers ?? []).contains(where: { $0 is BackgroundTap }) else { return }
            window.addGestureRecognizer(BackgroundTap())
        }
    }

    final class BackgroundTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            addTarget(self, action: #selector(dismissInput))
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }
        @objc private func dismissInput() { view?.endEditing(true) }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Do not interrupt typing, cursor selection, field-to-field focus, or the keyboard.
            guard touch.view?.window === view else { return false }
            var candidate = touch.view
            while let current = candidate {
                if current is UITextField || current is UITextView || current is UIInputView { return false }
                candidate = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
