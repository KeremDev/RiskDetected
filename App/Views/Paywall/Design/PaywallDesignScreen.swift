import SwiftUI

/// Claude Design paywall ekranının veri güdümlü gövdesi.
/// Aynı düzen hem PLUS hem PRO tasarımını üretir; fark
/// vurgu rengi, karşılaştırma sütunları ve çapraz satış kartıdır.
struct PaywallDesignPlanOption: Equatable {
    var title: String
    var price: String
    var caption: String
    var trialNote: String?
    var badgeLabel: String?
    var badgeDiscount: String?
}

struct PaywallDesignCTAState: Equatable {
    var title: String
    var isLoading: Bool
    var isDisabled: Bool
    var accessibilityIdentifier: String
}

struct PaywallDesignCrossSell: Equatable {
    enum Style: Equatable {
        case pro
        case plus
    }

    var style: Style
    var prefix: String
    var highlight: String
    var suffix: String
    var accessibilityIdentifier: String
}

struct PaywallDesignScreen: View {
    var screen: InAppPaywallScreen
    var heroLabel: String
    var tierName: String
    var accent: Color
    var selectedBackground: Color
    var showsTrialTimeline: Bool
    var trialDays: Int
    var timelineFeatures: [String]
    var comparisonLeft: PaywallDesignComparisonTable.Column
    var comparisonRight: PaywallDesignComparisonTable.Column
    var comparisonRows: [PaywallDesignComparisonRow]
    var annual: PaywallDesignPlanOption
    var monthly: PaywallDesignPlanOption
    var selectedBilling: InAppPaywallBilling
    var cta: PaywallDesignCTAState
    var notice: String?
    var errorMessage: String?
    var crossSell: PaywallDesignCrossSell?

    var onClose: () -> Void
    var onSelectBilling: (InAppPaywallBilling) -> Void
    var onCTA: () -> Void
    var onRestore: () -> Void
    var onTerms: () -> Void
    var onPrivacy: () -> Void
    var onManageSubscription: () -> Void
    var onCrossSell: () -> Void

    private var showsTimeline: Bool {
        showsTrialTimeline && selectedBilling == .yearly
    }

    /// PLUS tasarımında plan kartları ile çapraz satış arası 24pt, PRO'da 22pt.
    private var plansBottomPadding: CGFloat {
        screen == .plus ? 24 : 22
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    PaywallDesignHero(label: heroLabel, onClose: onClose)

                    PaywallDesignSocialProof()

                    if showsTimeline {
                        PaywallDesignTrialTimeline(
                            trialDays: trialDays,
                            tierName: tierName,
                            features: timelineFeatures
                        )
                    } else {
                        PaywallDesignComparisonTable(
                            left: comparisonLeft,
                            right: comparisonRight,
                            rows: comparisonRows
                        )
                    }

                    HStack(spacing: 10) {
                        planCard(annual, billing: .yearly, identifier: "in_app_paywall.plan.yearly")
                        planCard(monthly, billing: .monthly, identifier: "in_app_paywall.plan.monthly")
                    }
                    .padding(.top, 22)
                    .padding(.horizontal, PaywallDesignMetric.screenPadding)
                    .padding(.bottom, plansBottomPadding)

                    if let crossSell {
                        crossSellCard(crossSell)
                            .padding(.horizontal, PaywallDesignMetric.screenPadding)
                            .padding(.bottom, 22)
                    }
                }
            }

            PaywallDesignFooter(
                ctaTitle: cta.title,
                ctaAccessibilityIdentifier: cta.accessibilityIdentifier,
                isLoading: cta.isLoading,
                isDisabled: cta.isDisabled,
                accent: accent,
                notice: notice,
                errorMessage: errorMessage,
                onCTA: onCTA,
                onRestore: onRestore,
                onTerms: onTerms,
                onPrivacy: onPrivacy,
                onManageSubscription: onManageSubscription
            )
            .zIndex(2)
        }
        .background(Color.white)
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        // Ekran kimliği görünmez bir işaretçiye verilir; kök görünüme verilirse
        // SwiftUI bu kimliği tüm alt öğelere yayıp kendi kimliklerini eziyor.
        .overlay(alignment: .top) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("in_app_paywall.\(screen.rawValue)")
        }
    }

    private func planCard(
        _ option: PaywallDesignPlanOption,
        billing: InAppPaywallBilling,
        identifier: String
    ) -> some View {
        PaywallDesignPlanCard(
            title: option.title,
            price: option.price,
            caption: option.caption,
            trialNote: option.trialNote,
            badge: option.badgeLabel.map { (label: $0, discount: option.badgeDiscount ?? "") },
            accent: accent,
            selectedBackground: selectedBackground,
            isSelected: selectedBilling == billing,
            accessibilityIdentifier: identifier,
            onTap: { onSelectBilling(billing) }
        )
    }

    private func crossSellCard(_ crossSell: PaywallDesignCrossSell) -> some View {
        let isPro = crossSell.style == .pro
        let border = isPro ? PaywallDesignColor.green : PaywallDesignColor.amber
        let background = isPro ? PaywallDesignColor.greenCardBg : PaywallDesignColor.amberCardBg
        let highlightColor = isPro ? PaywallDesignColor.green : PaywallDesignColor.amberInk

        return PaywallDesignUpsellCard(
            icon: Group {
                if isPro {
                    PaywallDesignStarIcon(color: PaywallDesignColor.green)
                } else {
                    PaywallDesignCrownIcon(color: PaywallDesignColor.amber)
                }
            },
            borderColor: border,
            background: background,
            text: Text(crossSell.prefix)
                + Text(crossSell.highlight)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(highlightColor)
                + Text(crossSell.suffix),
            chevronColor: border,
            accessibilityIdentifier: crossSell.accessibilityIdentifier,
            onTap: onCrossSell
        )
    }
}
