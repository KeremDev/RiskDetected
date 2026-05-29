import SwiftUI

struct OnboardingPaywallV2View: View {
    var onClose: () -> Void
    var onSubscribe: () -> Void

    var body: some View {
        OBTimelinePaywallView(
            onStart: { _ in onSubscribe() },
            onRestore: onSubscribe,
            onTerms: {},
            onPrivacy: {},
            onDismiss: onClose
        )
    }
}

#Preview {
    OnboardingPaywallV2View(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
