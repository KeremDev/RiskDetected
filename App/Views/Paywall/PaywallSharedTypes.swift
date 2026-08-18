import SwiftUI

// Paywall ekranları arasında paylaşılan tipler.
// Claude Design paywall akışı (`PaywallDesignFlowView`) bu tipleri kullanır.

enum InAppPaywallScreen: String, Equatable {
    case plus
    case pro

    var tier: SubscriptionTier {
        switch self {
        case .plus: return .plus
        case .pro: return .pro
        }
    }

    var analyticsValue: String {
        switch self {
        case .plus: return "claude_plus"
        case .pro: return "claude_pro"
        }
    }
}

enum InAppPaywallBilling: String, Equatable {
    case monthly
    case yearly

    var title: String {
        switch self {
        case .monthly: return RDLocalization.string("paywall.in.app.paywall.view.aylik.aaed1eef", table: .paywall, fallback: "Aylık")
        case .yearly: return RDLocalization.string("paywall.in.app.paywall.view.yillik.ba990912", table: .paywall, fallback: "Yıllık")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .monthly: return RDLocalization.string("paywall.in.app.paywall.view.aylik.abonelik.c8bbf382", table: .paywall, fallback: "Aylık abonelik")
        case .yearly: return RDLocalization.string("paywall.in.app.paywall.view.yillik.abonelik.502c943c", table: .paywall, fallback: "Yıllık abonelik")
        }
    }
}

struct PaywallProcessingOverlay: View {
    let title: String
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Color.rdGreen)

                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: 300)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 28)
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.processing_overlay")
    }
}
