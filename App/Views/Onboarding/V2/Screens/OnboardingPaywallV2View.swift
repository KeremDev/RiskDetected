import SwiftUI

struct OnboardingPaywallV2View: View {
    var onClose: () -> Void
    var onSubscribe: () -> Void

    var body: some View {
        PaywallView(
            onClose: onClose,
            onSubscribe: onSubscribe,
            source: .onboardingV2,
            variantID: OnboardingPersonalPlanContext.variantID,
            layout: .plusFocused
        )
    }
}

#Preview {
    OnboardingPaywallV2View(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
