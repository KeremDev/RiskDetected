import SwiftUI

struct PaywallV2View: View {
    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil

    var body: some View {
        PaywallView(
            onClose: onClose,
            onSubscribe: onSubscribe,
            notice: notice,
            layout: .plusFocused
        )
    }
}

struct FreeAwarePaywallView: View {
    @EnvironmentObject private var app: AppState

    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil

    var body: some View {
        if app.currentTier.isPaid {
            PaywallView(
                onClose: onClose,
                onSubscribe: onSubscribe,
                notice: notice
            )
        } else {
            PaywallV2View(
                onClose: onClose,
                onSubscribe: onSubscribe,
                notice: notice
            )
        }
    }
}

#Preview {
    PaywallV2View(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
