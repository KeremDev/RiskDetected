import SwiftUI

// Dark trial invite screen — Kairo-style layout adapted with brand greens.
// Layout: title (top) → centered phone preview (middle) → no-payment line →
// big green CTA → footer legal links.
struct OBTrialInviteView: View {
    @EnvironmentObject private var app: AppState
    let onContinue: () -> Void

    @State private var funnelSessionID = UUID()
    @State private var didLogView = false
    // Phone deck swap state — every cycle, back phone slides forward and
    // current front recedes to back. Creates a continuous shuffle loop.
    @State private var swapped: Bool = false

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

    // Centered phone mockup container — image asset slot for screenshot.
    // Drop `TrialPreview` image into Assets.xcassets to fill.
    private var phonePreview: some View {
        ZStack {
            // Soft green glow behind phones
            Ellipse()
                .fill(Color.rdGreen.opacity(0.25))
                .frame(width: 280, height: 80)
                .blur(radius: 50)
                .offset(y: 160)

            // Phone A — front when !swapped, back when swapped
            phoneBezel
                .scaleEffect(isFront(.a) ? 1.0 : 0.92)
                .opacity(isFront(.a) ? 1.0 : 0.55)
                .rotationEffect(.degrees(isFront(.a) ? 0 : -8))
                .offset(x: isFront(.a) ? 0 : -32, y: isFront(.a) ? 0 : 12)
                .zIndex(isFront(.a) ? 1 : 0)

            // Phone B — front when swapped, back when !swapped
            phoneBezel
                .scaleEffect(isFront(.b) ? 1.0 : 0.92)
                .opacity(isFront(.b) ? 1.0 : 0.55)
                .rotationEffect(.degrees(isFront(.b) ? 0 : 8))
                .offset(x: isFront(.b) ? 0 : 32, y: isFront(.b) ? 0 : 12)
                .zIndex(isFront(.b) ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear { startSwapLoop() }
    }

    private enum DeckPhone { case a, b }

    private func isFront(_ phone: DeckPhone) -> Bool {
        switch phone {
        case .a: return !swapped
        case .b: return swapped
        }
    }

    private func startSwapLoop() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                withAnimation(.spring(response: 0.85, dampingFraction: 0.78)) {
                    swapped.toggle()
                }
            }
        }
    }

    private var phoneBezel: some View {
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
                        screenContent
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
    private var screenContent: some View {
        if UIImage(named: "TrialPreview") != nil {
            Image("TrialPreview")
                .resizable()
                .scaledToFill()
        } else {
            fallbackScreenPreview
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
