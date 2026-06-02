import SwiftUI

// Timeline paywall — trust-building trial flow.
// The screen explains the trial as a time sequence: today, reminder day,
// and billing day. Purchase/restore callbacks stay owned by the flow.
//
// Hooks:
//   onStart   — start trial / purchase
//   onRestore — restore purchases
//   onTerms   — open terms URL
//   onPrivacy — open privacy URL
//   onDismiss — close paywall (× button)
//
// Standalone for now; codex will wire to flow + IAP after approval.

struct OBTimelinePaywallView: View {
    var packages: [SubscriptionPlanPackage] = []
    var isWorking: Bool = false
    var noticeMessage: String?
    let onStart: (OBPlan) -> Void
    let onRestore: () -> Void
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onDismiss: () -> Void

    @State private var selectedPlan: OBPlan = .yearly
    @State private var timelineFlow: Bool = false

    private var priceLine: String {
        switch selectedPlan {
        case .yearly:  return yearlyPaywallLine
        case .monthly: return monthlyPaywallLine
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.rdPaper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    banner
                        .padding(.top, 54)
                        .padding(.bottom, 10)
                        .obStage(delay: 0.02)

                    planToggle
                        .obStage(delay: 0.12)

                    timeline
                        .obStage(delay: 0.12)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, noticeMessage == nil && !isWorking ? 138 : 182)
            }

            bottomBar
                .frame(maxHeight: .infinity, alignment: .bottom)

        }
        .accessibilityIdentifier("onboarding.timeline_paywall")
    }

    // MARK: - Header

    private var headerSubtitle: String {
        switch selectedPlan {
        case .yearly:
            return yearlyPaywallLine
        case .monthly:
            return "Aylık plan hemen başlar. İstediğin zaman iptal edebilirsin."
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ücretsiz Deneme Nasıl Çalışır")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                Text(headerSubtitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            OBPrimaryButton(
                title: isWorking ? "İşleniyor..." : (selectedPlan == .yearly ? "₺0,00'ye dene" : "Aboneliği başlat"),
                trailingIcon: "arrow.right",
                style: .onyx,
                accessibilityID: "onboarding.timeline_paywall.cta"
            ) {
                onStart(selectedPlan)
            }
            .disabled(isWorking)
            .opacity(isWorking ? 0.72 : 1)

            if isWorking || noticeMessage != nil {
                paywallNotice
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 14) {
                Button {
                    OBHaptic.light(); onRestore()
                } label: {
                    Text("Geri yükle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                }
                .disabled(isWorking)
                .opacity(isWorking ? 0.55 : 1)
                .accessibilityIdentifier("onboarding.timeline_paywall.restore")

                Circle().fill(Color.rdSlate.opacity(0.35)).frame(width: 3, height: 3)

                Button {
                    OBHaptic.soft(); onTerms()
                } label: {
                    Text("Kullanım Şartları")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                .disabled(isWorking)
                .accessibilityIdentifier("onboarding.timeline_paywall.terms")

                Circle().fill(Color.rdSlate.opacity(0.35)).frame(width: 3, height: 3)

                Button {
                    OBHaptic.soft(); onPrivacy()
                } label: {
                    Text("Gizlilik Politikası")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                .disabled(isWorking)
                .accessibilityIdentifier("onboarding.timeline_paywall.privacy")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [
                    Color.rdPaper.opacity(0),
                    Color.rdPaper.opacity(0.96),
                    Color.rdPaper
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .animation(.obSpring, value: selectedPlan)
        .animation(.obSpring, value: isWorking)
        .animation(.obSpring, value: noticeMessage)
    }

    @ViewBuilder
    private var paywallNotice: some View {
        HStack(spacing: 8) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.rdBlack)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.rdHigh)
            }

            Text(isWorking ? "Satın alımlar kontrol ediliyor..." : noticeMessage ?? "")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .accessibilityIdentifier("onboarding.timeline_paywall.notice")
    }

    // MARK: - Plan toggle

    private var planToggle: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                planPill(.yearly, label: "Yıllık")
                planPill(.monthly, label: "Aylık")
            }
            .padding(4)
            .background(Color.rdFog)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.rdLine, lineWidth: 1))
            .frame(width: 210)

            Text(selectedPlan == .yearly ? "%17 İndirim" : monthlyPaywallLine)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(selectedPlan == .yearly ? Color.rdGreen : Color.rdSlate)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }

    private func planPill(_ plan: OBPlan, label: String) -> some View {
        let selected = selectedPlan == plan
        return Button {
            OBHaptic.light()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                selectedPlan = plan
            }
        } label: {
            Text(label)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.rdBlack : Color.rdSlate)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .frame(height: 25)
            .background(selected ? Color.white : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? Color.rdBlack.opacity(0.12) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.timeline_paywall.plan.\(plan.rawValue)")
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        if selectedPlan == .yearly {
            yearlyTimeline
        } else {
            monthlyTimeline
        }
    }

    private var yearlyTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineStep(
                index: 0,
                icon: "lock.shield.fill",
                accent: Color.rdGreen,
                day: "Bugün",
                detail: "Plus özellikleri açılır, ücret alınmaz.",
                featureItems: [
                    "Detaylı Analiz",
                    "Risk Analizi (Fine-Kinney ve 5*5)",
                    "PDF/Excel Rapor"
                ],
                isLast: false
            )
            timelineStep(
                index: 1,
                icon: "bell.fill",
                accent: Color(hex: "#F0A400"),
                day: "5. Gün",
                detail: "Denemen bitmeden sana hatırlatma göndeririz.",
                isLast: false
            )
            timelineStep(
                index: 2,
                icon: "crown.fill",
                accent: Color(hex: "#F0A400"),
                day: "7. Gün",
                detail: "Devam edersen yıllık plan başlar. İstediğin zaman iptal edebilirsin.",
                isLast: true
            )
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .rdCardShadow()
    }

    private var monthlyTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineStep(
                index: 0,
                icon: "lock.shield.fill",
                accent: Color(hex: "#F0A400"),
                day: "Bugün",
                detail: "Tüm özellikler hemen aktif olur, ödeme başlar.",
                isLast: false
            )
            timelineStep(
                index: 1,
                icon: "calendar.badge.checkmark",
                accent: Color.rdGreen,
                day: "Her ay",
                detail: monthlyRenewalLine,
                isLast: true
            )
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .rdCardShadow()
    }

    private var yearlyPrice: String {
        displayPrice(for: .yearly, fallback: OBTrialPriceCopy.yearlyPrice)
    }

    private var monthlyPrice: String {
        displayPrice(for: .monthly, fallback: OBTrialPriceCopy.monthlyPrice)
    }

    private var yearlyMonthlyEquivalent: String {
        guard let package = plusPackage(for: .yearly),
              let monthlyEquivalent = package.monthlyEquivalentPrice,
              !Self.shouldUseTRYFallback(for: monthlyEquivalent) else {
            return OBTrialPriceCopy.yearlyMonthlyEquivalent
        }
        return monthlyEquivalent.hasSuffix("/ay") ? monthlyEquivalent : "\(monthlyEquivalent)/ay"
    }

    private var yearlyPaywallLine: String {
        "7 gün ücretsiz, sonra \(yearlyPrice) (\(yearlyMonthlyEquivalent))"
    }

    private var monthlyPaywallLine: String {
        "\(monthlyPrice)/ay — istediğin zaman iptal"
    }

    private var monthlyRenewalLine: String {
        "\(monthlyPrice) otomatik yenilenir. İstediğin zaman iptal edebilirsin."
    }

    private func displayPrice(for plan: OBPlan, fallback: String) -> String {
        guard let package = plusPackage(for: plan) else { return fallback }
        return Self.shouldUseTRYFallback(for: package.price) ? fallback : package.price
    }

    private func plusPackage(for plan: OBPlan) -> SubscriptionPlanPackage? {
        packages
            .filter { $0.tier == .plus }
            .first { $0.matchesOnboardingBilling(plan) }
    }

    private static func shouldUseTRYFallback(for price: String) -> Bool {
        let trimmed = price.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let locale = Locale.current
        guard locale.region?.identifier == "TR" else { return false }

        let normalized = trimmed
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .uppercased(with: Locale(identifier: "en_US"))
        return normalized.contains("$") || normalized.contains("USD")
    }

    private func timelineStep(
        index: Int,
        icon: String,
        accent: Color,
        day: String,
        detail: String,
        featureItems: [String] = [],
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(accent, lineWidth: 1.6)
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }

                if !isLast {
                    timelineConnector(
                        accent: accent,
                        height: featureItems.isEmpty ? 50 : 108
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(day)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rdOnyx)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !featureItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(featureItems, id: \.self) { item in
                            HStack(spacing: 7) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.rdGreen)
                                Text(item)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.rdBlack)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : 12)
        }
        .obStage(delay: 0.24 + Double(index) * 0.08)
        .onAppear { startTimelineFlow() }
    }

    private func timelineConnector(accent: Color, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(accent.opacity(0.18))
                .frame(width: 4, height: height)

            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0),
                                accent.opacity(0.85),
                                accent.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: max(22, geo.size.height * 0.36))
                    .offset(y: timelineFlow ? geo.size.height : -geo.size.height * 0.4)
            }
            .frame(width: 4, height: height)
            .clipShape(Capsule())
        }
    }

    private func startTimelineFlow() {
        timelineFlow = false
        withAnimation(.linear(duration: 1.45).repeatForever(autoreverses: false)) {
            timelineFlow = true
        }
    }

}

// Banner bottom: organic wavy edge with subtle bumps — softer than wedges,
// blends gradient into white area smoothly.
private struct BannerWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - 24))

        // Wavy bottom edge — 3 humps via successive quadratic curves.
        // Control points alternate above/below to create organic dips.
        p.addQuadCurve(
            to: CGPoint(x: w * 0.74, y: h - 12),
            control: CGPoint(x: w * 0.90, y: h + 8)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.50, y: h - 30),
            control: CGPoint(x: w * 0.62, y: h - 52)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.26, y: h - 14),
            control: CGPoint(x: w * 0.38, y: h + 8)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0, y: h - 32),
            control: CGPoint(x: w * 0.12, y: h - 50)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Helmet shapes (built from scratch, no SF Symbol dependency)

private struct HelmetShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Dome top
        p.move(to: CGPoint(x: w * 0.18, y: h * 0.72))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.72),
            control: CGPoint(x: w * 0.50, y: h * 0.05)
        )
        // Right side curve down
        p.addQuadCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.78),
            control: CGPoint(x: w * 0.92, y: h * 0.74)
        )
        // Brim bottom right
        p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.86))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.78, y: h * 0.94),
            control: CGPoint(x: w * 0.90, y: h * 0.94)
        )
        // Brim across bottom
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.94))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.04, y: h * 0.86),
            control: CGPoint(x: w * 0.10, y: h * 0.94)
        )
        p.addLine(to: CGPoint(x: w * 0.04, y: h * 0.78))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.18, y: h * 0.72),
            control: CGPoint(x: w * 0.08, y: h * 0.74)
        )
        p.closeSubpath()
        return p
    }
}

private struct HelmetHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Crescent highlight on top dome
        p.move(to: CGPoint(x: w * 0.26, y: h * 0.40))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.74, y: h * 0.40),
            control: CGPoint(x: w * 0.50, y: h * 0.10)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.30, y: h * 0.46),
            control: CGPoint(x: w * 0.50, y: h * 0.28)
        )
        p.closeSubpath()
        return p
    }
}

private struct HelmetRidgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Center ridge line from front to back of dome
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.08))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.74),
            control: CGPoint(x: w * 0.50, y: h * 0.40)
        )
        // Brim seam
        p.move(to: CGPoint(x: w * 0.06, y: h * 0.82))
        p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.82))
        return p
    }
}

#Preview {
    OBTimelinePaywallView(
        isWorking: false,
        noticeMessage: nil,
        onStart: { _ in },
        onRestore: {},
        onTerms: {},
        onPrivacy: {},
        onDismiss: {}
    )
}

// MARK: - Hardhat vector (Canvas-rendered, reliable across iOS versions)

private struct HardhatVector: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // ── Color palette ─────────────────────────────────────
            let lightGreen = Color(hex: "#6FE99A")
            let midGreen = Color.rdGreen
            let darkGreen = Color(hex: "#007D1F")
            let veryDark = Color(hex: "#004B12")
            let shadowGreen = Color(hex: "#003A0D")

            // ── Brim under-shadow (inside lip visible under brim) ─
            var underShadow = Path()
            underShadow.addEllipse(in: CGRect(
                x: w * 0.06, y: h * 0.84,
                width: w * 0.88, height: h * 0.08
            ))
            ctx.fill(underShadow, with: .color(veryDark.opacity(0.55)))

            // ── Brim — wide flat oval base with subtle front curve ─
            var brim = Path()
            brim.move(to: CGPoint(x: w * 0.02, y: h * 0.82))
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.98, y: h * 0.82),
                control: CGPoint(x: w * 0.50, y: h * 0.78)
            )
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.92, y: h * 0.92),
                control: CGPoint(x: w * 0.98, y: h * 0.90)
            )
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.08, y: h * 0.92),
                control: CGPoint(x: w * 0.50, y: h * 0.96)
            )
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.02, y: h * 0.82),
                control: CGPoint(x: w * 0.02, y: h * 0.86)
            )
            brim.closeSubpath()
            ctx.fill(
                brim,
                with: .linearGradient(
                    Gradient(colors: [midGreen, darkGreen, veryDark]),
                    startPoint: CGPoint(x: w * 0.5, y: h * 0.80),
                    endPoint: CGPoint(x: w * 0.5, y: h * 0.92)
                )
            )

            // Brim top highlight (catches light)
            var brimHL = Path()
            brimHL.move(to: CGPoint(x: w * 0.16, y: h * 0.825))
            brimHL.addQuadCurve(
                to: CGPoint(x: w * 0.84, y: h * 0.825),
                control: CGPoint(x: w * 0.50, y: h * 0.805)
            )
            ctx.stroke(brimHL, with: .color(lightGreen.opacity(0.55)), lineWidth: 1.6)

            // Brim front-edge shadow under dome
            var brimShadow = Path()
            brimShadow.move(to: CGPoint(x: w * 0.10, y: h * 0.81))
            brimShadow.addQuadCurve(
                to: CGPoint(x: w * 0.90, y: h * 0.81),
                control: CGPoint(x: w * 0.50, y: h * 0.83)
            )
            ctx.stroke(brimShadow, with: .color(shadowGreen.opacity(0.45)), lineWidth: 2.2)

            // ── Dome — main body with proper hardhat curvature ─
            var dome = Path()
            // Start at left base, sweep up and over
            dome.move(to: CGPoint(x: w * 0.14, y: h * 0.78))
            // Left side curve up
            dome.addCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.08),
                control1: CGPoint(x: w * 0.10, y: h * 0.55),
                control2: CGPoint(x: w * 0.20, y: h * 0.14)
            )
            // Right side curve down
            dome.addCurve(
                to: CGPoint(x: w * 0.86, y: h * 0.78),
                control1: CGPoint(x: w * 0.80, y: h * 0.14),
                control2: CGPoint(x: w * 0.90, y: h * 0.55)
            )
            // Right flank to brim
            dome.addQuadCurve(
                to: CGPoint(x: w * 0.94, y: h * 0.82),
                control: CGPoint(x: w * 0.90, y: h * 0.81)
            )
            // Across bottom
            dome.addLine(to: CGPoint(x: w * 0.06, y: h * 0.82))
            // Left flank back up
            dome.addQuadCurve(
                to: CGPoint(x: w * 0.14, y: h * 0.78),
                control: CGPoint(x: w * 0.10, y: h * 0.81)
            )
            dome.closeSubpath()

            // Fill dome with vertical gradient (light top → dark bottom)
            ctx.fill(
                dome,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: lightGreen, location: 0.0),
                        .init(color: midGreen, location: 0.35),
                        .init(color: darkGreen, location: 0.85),
                        .init(color: veryDark, location: 1.0)
                    ]),
                    startPoint: CGPoint(x: w * 0.5, y: h * 0.05),
                    endPoint: CGPoint(x: w * 0.5, y: h * 0.82)
                )
            )

            // Left-side ambient shadow (gives 3D feel)
            var leftShade = Path()
            leftShade.move(to: CGPoint(x: w * 0.14, y: h * 0.78))
            leftShade.addCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.08),
                control1: CGPoint(x: w * 0.10, y: h * 0.55),
                control2: CGPoint(x: w * 0.20, y: h * 0.14)
            )
            leftShade.addCurve(
                to: CGPoint(x: w * 0.30, y: h * 0.78),
                control1: CGPoint(x: w * 0.36, y: h * 0.20),
                control2: CGPoint(x: w * 0.24, y: h * 0.50)
            )
            leftShade.closeSubpath()
            ctx.fill(leftShade, with: .color(shadowGreen.opacity(0.18)))

            // ── Specular highlight (upper-right) ─
            var spec = Path()
            spec.move(to: CGPoint(x: w * 0.42, y: h * 0.18))
            spec.addQuadCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.42),
                control: CGPoint(x: w * 0.78, y: h * 0.16)
            )
            spec.addQuadCurve(
                to: CGPoint(x: w * 0.46, y: h * 0.28),
                control: CGPoint(x: w * 0.58, y: h * 0.38)
            )
            spec.closeSubpath()
            ctx.fill(spec, with: .color(Color.white.opacity(0.42)))

            // Secondary highlight band
            var hl2 = Path()
            hl2.move(to: CGPoint(x: w * 0.30, y: h * 0.55))
            hl2.addQuadCurve(
                to: CGPoint(x: w * 0.40, y: h * 0.50),
                control: CGPoint(x: w * 0.34, y: h * 0.50)
            )
            ctx.stroke(hl2, with: .color(lightGreen.opacity(0.65)), lineWidth: 2.5)

            // ── Center ridge (top crown line) ─
            var ridge = Path()
            ridge.move(to: CGPoint(x: w * 0.50, y: h * 0.09))
            ridge.addQuadCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.78),
                control: CGPoint(x: w * 0.50, y: h * 0.45)
            )
            ctx.stroke(ridge, with: .color(darkGreen.opacity(0.40)), lineWidth: 1.8)

            // Ridge highlight
            var ridgeHL = Path()
            ridgeHL.move(to: CGPoint(x: w * 0.515, y: h * 0.12))
            ridgeHL.addQuadCurve(
                to: CGPoint(x: w * 0.515, y: h * 0.45),
                control: CGPoint(x: w * 0.515, y: h * 0.30)
            )
            ctx.stroke(ridgeHL, with: .color(Color.white.opacity(0.45)), lineWidth: 1)

            // ── Side air vents (rectangular slots, more anatomical) ─
            for vx in [w * 0.28, w * 0.68] {
                let slot = Path(roundedRect: CGRect(x: vx - 5, y: h * 0.50, width: 10, height: 16),
                                cornerRadius: 2.5)
                ctx.fill(slot, with: .color(shadowGreen.opacity(0.55)))
                // inner shadow
                let inner = Path(roundedRect: CGRect(x: vx - 4, y: h * 0.51, width: 8, height: 13),
                                 cornerRadius: 2)
                ctx.fill(inner, with: .color(Color.black.opacity(0.30)))
            }

            // ── Front logo plate (subtle, white) ─
            let plateRect = CGRect(x: w * 0.43, y: h * 0.60, width: w * 0.14, height: h * 0.08)
            ctx.fill(
                Path(roundedRect: plateRect, cornerRadius: 2.5),
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.75)]),
                    startPoint: CGPoint(x: plateRect.midX, y: plateRect.minY),
                    endPoint: CGPoint(x: plateRect.midX, y: plateRect.maxY)
                )
            )

            // ── Rim outline (crisp edge for definition) ─
            ctx.stroke(dome, with: .color(shadowGreen.opacity(0.32)), lineWidth: 0.8)
        }
    }
}

// MARK: - Realistic rope

private struct RealisticRope: View {
    let length: CGFloat
    private let thickness: CGFloat = 6

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // Base shape — cylindrical rope (rounded rect, full height)
            let ropePath = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                                cornerRadius: w * 0.5)

            // Fill with horizontal gradient — darker at edges, lighter center,
            // creates cylindrical depth illusion.
            ctx.fill(
                ropePath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: "#5A3F22"), location: 0.0),
                        .init(color: Color(hex: "#A07A4E"), location: 0.45),
                        .init(color: Color(hex: "#C49968"), location: 0.55),
                        .init(color: Color(hex: "#6E4D2A"), location: 1.0)
                    ]),
                    startPoint: CGPoint(x: 0, y: h * 0.5),
                    endPoint: CGPoint(x: w, y: h * 0.5)
                )
            )

            // Clip subsequent draws to rope shape — twist lines stay inside
            var stripes = ctx
            stripes.clip(to: ropePath)

            // Twist pattern — diagonal stripes mimicking braided fibers
            let step: CGFloat = 5
            for y in stride(from: -w * 2, through: h + w * 2, by: step) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: w, y: y + w * 1.4))
                stripes.stroke(line, with: .color(Color.black.opacity(0.22)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }

            // Lighter highlight stripes interleaved (offset half-step)
            for y in stride(from: -w * 2 + step / 2, through: h + w * 2, by: step) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: w, y: y + w * 1.4))
                stripes.stroke(line, with: .color(Color.white.opacity(0.12)),
                               style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            }

            // Rim edge stroke for definition
            ctx.stroke(ropePath, with: .color(Color(hex: "#3A2510").opacity(0.55)),
                       lineWidth: 0.6)
        }
        .frame(width: thickness, height: length)
    }
}
