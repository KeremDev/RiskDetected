import SwiftUI

struct OnboardingPaywallV2View: View {
    var onClose: () -> Void
    var onSubscribe: () -> Void

    var body: some View {
        PaywallView(
            onClose: onClose,
            onSubscribe: onSubscribe,
            layout: .plusFocused
        )
    }
}

#Preview {
    OnboardingPaywallV2View(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
