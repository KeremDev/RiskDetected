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
    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil

    var body: some View {
        InAppPaywallView(
            onClose: onClose,
            onSubscribe: onSubscribe,
            notice: notice
        )
    }
}

#Preview {
    PaywallV2View(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
