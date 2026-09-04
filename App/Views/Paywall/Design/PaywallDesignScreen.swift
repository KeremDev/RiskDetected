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
    var timelineFeatures: [PaywallDesignFeature]
    var comparisonLeft: PaywallDesignComparisonTable.Column
    var comparisonRight: PaywallDesignComparisonTable.Column
    var comparisonRows: [PaywallDesignComparisonRow]
    var annual: PaywallDesignPlanOption
    var monthly: PaywallDesignPlanOption
    var selectedBilling: InAppPaywallBilling
    var cta: PaywallDesignCTAState
    var notice: String?
    var errorMessage: String?
    /// Alt bardaki otomatik yenileme cümlesinin devamına eklenen seçili plan fiyatı.
    var renewalPrice: String?
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

    var body: some View {
        RDAdaptiveContainer { profile in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    PaywallDesignHero(
                        label: heroLabel,
                        height: profile.paywallHeroHeight,
                        onClose: onClose
                    )

                    PaywallDesignSocialProof()

                    if showsTimeline {
                        PaywallDesignTrialTimeline(
                            trialDays: trialDays,
                            tierName: tierName,
                            accent: accent
                        )
                    } else {
                        PaywallDesignComparisonTable(
                            left: comparisonLeft,
                            right: comparisonRight,
                            rows: comparisonRows
                        )
                    }

                    // Şerit her iki anlatımın da altında durur: PLUS/PRO, yıllık/aylık
                    // fark etmeksizin paketin kapsamı akarken görünür.
                    PaywallDesignFeatureMarquee(
                        features: timelineFeatures,
                        accent: accent
                    )

                    AnyLayout(
                        profile.prefersStackedControls
                            ? AnyLayout(VStackLayout(spacing: 12))
                            : AnyLayout(HStackLayout(spacing: 10))
                    ) {
                        planCard(annual, billing: .yearly, identifier: "in_app_paywall.plan.yearly")
                        planCard(monthly, billing: .monthly, identifier: "in_app_paywall.plan.monthly")
                    }
                    .padding(.top, profile.isCompact ? 16 : 22)
                    .padding(.horizontal, profile.horizontalPadding)
                    .padding(.bottom, profile.isCompact ? 18 : 24)

                    if let crossSell {
                        crossSellCard(crossSell)
                            .padding(.horizontal, profile.horizontalPadding)
                            .padding(.bottom, profile.sectionSpacing)
                    }

                    PaywallDesignLegalFooter(
                        renewalPrice: renewalPrice,
                        onRestore: onRestore,
                        onTerms: onTerms,
                        onPrivacy: onPrivacy,
                        onManageSubscription: onManageSubscription
                    )
                    .padding(.horizontal, profile.horizontalPadding)
                    .padding(.bottom, profile.sectionSpacing)
                }
            }
            // Ekran değiştiğinde (PLUS ↔ PRO) kaydırma konumu başa dönsün;
            // aksi halde kullanıcı yeni ekranın ortasına düşüyor.
            .id(screen)

            .safeAreaInset(edge: .bottom, spacing: 0) {
                PaywallDesignFooter(
                    ctaTitle: cta.title,
                    ctaAccessibilityIdentifier: cta.accessibilityIdentifier,
                    isLoading: cta.isLoading,
                    isDisabled: cta.isDisabled,
                    accent: accent,
                    notice: notice,
                    errorMessage: errorMessage,
                    onCTA: onCTA
                )
            }
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        // Ekran kimliği görünmez bir işaretçiye verilir; kök görünüme verilirse
        // SwiftUI bu kimliği tüm alt öğelere yayıp kendi kimliklerini eziyor.
        .overlay(alignment: .top) {
            if screen == .plus {
                screenMarker("in_app_paywall.plus")
            } else {
                screenMarker("in_app_paywall.pro")
            }
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
                    .font(RDTypography.font(size: 13, weight: .heavy))
                    .foregroundColor(highlightColor)
                + Text(crossSell.suffix),
            chevronColor: border,
            accessibilityIdentifier: crossSell.accessibilityIdentifier,
            onTap: onCrossSell
        )
    }

    private func screenMarker(_ identifier: String) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(identifier)
            .id(identifier)
    }
}
