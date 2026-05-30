import SwiftUI

// Dark trial invite screen — Kairo-style layout adapted with brand greens.
// Layout: title (top) → centered phone preview (middle) → no-payment line →
// big green CTA → footer legal links.
struct OBTrialInviteView: View {
    @EnvironmentObject private var app: AppState
    let onContinue: () -> Void

    @State private var funnelSessionID = UUID()
    @State private var didLogView = false
    // Phone deck state — every cycle, the next phone slides forward while
    // the previous front recedes. Creates a continuous three-screen loop.
    @State private var frontPhone: DeckPhone = .a

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer(minLength: 32)

                title
                    .padding(.horizontal, 28)
                    .obStage(delay: 0.08)

                Spacer(minLength: 24)

                phonePreview
                    .obStage(delay: 0.2)

                Spacer(minLength: 28)

                noPaymentLine
                    .padding(.bottom, 14)
                    .obStage(delay: 0.32)

                OBPrimaryButton(title: "₺0,00'ye dene", trailingIcon: "arrow.right", style: .onyx, accessibilityID: "onboarding.trial_invite.cta") {
                    record(.trialInviteCtaTap)
                    onContinue()
                }
                .padding(.horizontal, 24)
                .obStage(delay: 0.4)

                Text("Taahhüt yok, istediğin zaman iptal.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .obStage(delay: 0.44)

                footerLinks
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .obStage(delay: 0.48)
            }
        }
        .onAppear { logViewIfNeeded() }
        .accessibilityIdentifier("onboarding.trial_invite")
    }

    // MARK: - Pieces

    private var backdrop: some View {
        ZStack {
            Color.rdPaper
            RadialGradient(
                colors: [Color.rdGreen.opacity(0.10), .clear],
                center: .top, startRadius: 0, endRadius: 320
            )
        }
        .ignoresSafeArea()
    }

    private var title: some View {
        VStack(spacing: 8) {
            (Text("Uygulamayı ").foregroundColor(Color.rdOnyx)
             + Text("ücretsiz").foregroundColor(Color.rdGreen))
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
            Text("denemeni istiyoruz")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(Color.rdOnyx)
        }
        .multilineTextAlignment(.center)
    }

    // Centered phone mockup container — optional asset slots for screenshots.
    // Drop `TrialPreviewA`, `TrialPreviewB` and `TrialPreviewC` into Assets.xcassets to fill.
    private var phonePreview: some View {
        ZStack {
            // Soft green glow behind phones
            Ellipse()
                .fill(Color.rdGreen.opacity(0.25))
                .frame(width: 280, height: 80)
                .blur(radius: 50)
                .offset(y: 160)

            ForEach(DeckPhone.allCases) { phone in
                let placement = deckPlacement(for: phone)
                phoneBezel(for: phone)
                    .scaleEffect(placement.scale)
                    .opacity(placement.opacity)
                    .rotationEffect(.degrees(placement.rotation))
                    .offset(x: placement.xOffset, y: placement.yOffset)
                    .zIndex(placement.zIndex)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { startSwapLoop() }
    }

    private enum DeckPhone: Int, CaseIterable, Identifiable {
        case a
        case b
        case c

        var id: Int { rawValue }

        var next: DeckPhone {
            let nextRaw = (rawValue + 1) % Self.allCases.count
            return Self(rawValue: nextRaw) ?? .a
        }
    }

    private struct DeckPlacement {
        let scale: CGFloat
        let opacity: Double
        let rotation: Double
        let xOffset: CGFloat
        let yOffset: CGFloat
        let zIndex: Double
    }

    private func deckPlacement(for phone: DeckPhone) -> DeckPlacement {
        let relativeIndex = (phone.rawValue - frontPhone.rawValue + DeckPhone.allCases.count) % DeckPhone.allCases.count
        switch relativeIndex {
        case 0:
            return DeckPlacement(scale: 1.0, opacity: 1.0, rotation: 0, xOffset: 0, yOffset: 0, zIndex: 3)
        case 1:
            return DeckPlacement(scale: 0.90, opacity: 0.46, rotation: 8, xOffset: 38, yOffset: 14, zIndex: 1)
        default:
            return DeckPlacement(scale: 0.90, opacity: 0.46, rotation: -8, xOffset: -38, yOffset: 14, zIndex: 0)
        }
    }

    private func startSwapLoop() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                withAnimation(.spring(response: 0.85, dampingFraction: 0.78)) {
                    frontPhone = frontPhone.next
                }
            }
        }
    }

    private func phoneBezel(for phone: DeckPhone) -> some View {
        RoundedRectangle(cornerRadius: 38, style: .continuous)
            .fill(Color(hex: "#16191A"))
            .frame(width: 230, height: 460)
            .overlay(
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(hex: "#0B0D0E"))
                    .overlay(
                        screenContent(for: phone)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    )
                    .padding(10)
            )
            .overlay(
                Capsule()
                    .fill(Color.black)
                    .frame(width: 90, height: 26)
                    .offset(y: -212)
            )
    }

    // Screen mockup — image asset takes priority if available, else
    // shows a branded fallback preview (logo + mini risk card stack).
    @ViewBuilder
    private func screenContent(for phone: DeckPhone) -> some View {
        let assetName = trialPreviewAssetName(for: phone)
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFill()
        } else {
            fallbackScreenPreview
        }
    }

    private func trialPreviewAssetName(for phone: DeckPhone) -> String {
        switch phone {
        case .a: return "TrialPreviewA"
        case .b: return "TrialPreviewB"
        case .c: return "TrialPreviewC"
        }
    }

    private var fallbackScreenPreview: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 36)

            RDLogo(size: 22)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                miniRiskRow(level: .critical, label: "Yüksekte çalışma")
                miniRiskRow(level: .high, label: "KKD eksikliği")
                miniRiskRow(level: .medium, label: "Aydınlatma")
            }
            .padding(.horizontal, 16)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                Text("Rapor hazır")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.rdGreen)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#101413"))
    }

    private func miniRiskRow(level: RiskLevel, label: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(level.color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Text(level.shortLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(level.color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(level.bgColor.opacity(0.18))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var noPaymentLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.rdOnyx)
            Text("Şu an ödeme yok")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.rdOnyx)
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 16) {
            footerLink("Gizlilik Politikası")
            footerLink("Geri Yükle")
            footerLink("Şartlar")
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func footerLink(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color.rdSlate)
            .underline()
    }

    // MARK: - Telemetry

    private func logViewIfNeeded() {
        guard !didLogView else { return }
        didLogView = true
        record(.trialInviteView)
    }

    private func record(_ event: PaywallEventName) {
        PaywallEventService.shared.record(
            event,
            funnelSessionID: funnelSessionID,
            source: .onboardingV2,
            variantID: OnboardingPersonalPlanContext.variantID,
            segmentKey: nil,
            selectedTier: .plus,
            billing: nil,
            productIdentifier: nil,
            metadata: PaywallEventMetadata(
                layout: "onboarding_trial_invite",
                currentTier: app.currentTier.rawValue,
                selectedPackageID: nil,
                noticePresent: false,
                errorMessage: nil,
                contextHeadline: "Uygulamayı ücretsiz denemeni istiyoruz",
                purchaseError: nil
            )
        )
    }
}

#Preview {
    OBTrialInviteView(onContinue: {})
        .environmentObject(AppState())
}
