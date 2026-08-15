import SwiftUI

// Dark trial invite screen — Kairo-style layout adapted with brand greens.
// Layout: title (top) → centered phone preview (middle) → no-payment line →
// big green CTA → footer legal links.
struct OBTrialInviteView: View {
    @EnvironmentObject private var app: AppState
    let onContinue: () -> Void
    var onDismiss: () -> Void = {}
    var onPrivacy: () -> Void = {}
    var onTerms: () -> Void = {}
    var onRestore: () -> Void = {}

    @State private var funnelSessionID = UUID()
    @State private var didLogView = false
    // Phone deck state — every cycle, the next phone slides forward while
    // the previous front recedes. Creates a continuous three-screen loop.
    @State private var frontPhone: DeckPhone = .a

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

                OBPrimaryButton(title: RDLocalization.string("onboarding.obtrial.invite.view.0.00.ye.dene.c364ad31", table: .onboarding, fallback: "0.00 TL'ye dene"), trailingIcon: "arrow.right", style: .onyx, accessibilityID: "onboarding.trial_invite.cta") {
                    record(.trialInviteCtaTap)
                    onContinue()
                }
                .padding(.horizontal, 24)
                .obStage(delay: 0.4)

                Button {
                    OBHaptic.soft()
                    onDismiss()
                } label: {
                    Text(RDLocalization.string("onboarding.obtimeline.paywall.view.simdilik.ucretsiz.devam.et.b59d7d99", table: .onboarding, fallback: "Ücretsiz Devam Et"))
                        .font(.system(size: RDFontScale.size(12), weight: .semibold))
                        .foregroundStyle(Color.rdSlate.opacity(0.72))
                        .underline(true, color: Color.rdSlate.opacity(0.46))
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.trial_invite.continue_free")
                .obStage(delay: 0.44)

                footerLinks
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .obStage(delay: 0.48)
            }

            dismissButton
                .padding(.top, 12)
                .padding(.trailing, 18)
        }
        .onAppear { logViewIfNeeded() }
        .accessibilityElement(children: .contain)
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
        (Text(RDLocalization.string("onboarding.obtrial.invite.view.uygulamayi.faee4cf2", table: .onboarding, fallback: "Ücretsiz ")).foregroundColor(Color.rdGreen)
         + Text(RDLocalization.string("onboarding.obtrial.invite.view.ucretsiz.84c94af9", table: .onboarding, fallback: "Denemenizi İstiyoruz")).foregroundColor(Color.rdOnyx))
            .font(.system(size: RDFontScale.size(26), weight: .semibold))
            .tracking(-0.6)
            .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
    }

    private var dismissButton: some View {
        Button {
            OBHaptic.soft()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: RDFontScale.size(13), weight: .bold))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.86))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.rdLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RDLocalization.string("onboarding.obtimeline.paywall.view.simdilik.ucretsiz.devam.et.871ae28f", table: .onboarding, fallback: "Şimdilik ücretsiz devam et"))
        .accessibilityIdentifier("onboarding.trial_invite.dismiss")
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
        case .a: return RDLocalization.string("onboarding.obtrial.invite.view.trialpreviewa.4c7dce10", table: .onboarding, fallback: "TrialPreviewA")
        case .b: return RDLocalization.string("onboarding.obtrial.invite.view.trialpreviewb.d724a85f", table: .onboarding, fallback: "TrialPreviewB")
        case .c: return RDLocalization.string("onboarding.obtrial.invite.view.trialpreviewc.fb16d819", table: .onboarding, fallback: "TrialPreviewC")
        }
    }

    private var fallbackScreenPreview: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 36)

            RDLogo(size: 22)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                miniRiskRow(level: .critical, label: RDLocalization.string("onboarding.obtrial.invite.view.yuksekte.calisma.faca06c7", table: .onboarding, fallback: "Yüksekte çalışma"))
                miniRiskRow(level: .high, label: RDLocalization.string("onboarding.obtrial.invite.view.kkd.eksikligi.b99dabce", table: .onboarding, fallback: "KKD eksikliği"))
                miniRiskRow(level: .medium, label: RDLocalization.string("onboarding.obtrial.invite.view.aydinlatma.ee4f3377", table: .onboarding, fallback: "Aydınlatma"))
            }
            .padding(.horizontal, 16)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: RDFontScale.size(13)))
                Text(RDLocalization.string("onboarding.obtrial.invite.view.rapor.hazir.2cda9278", table: .onboarding, fallback: "Rapor hazır"))
                    .font(.system(size: RDFontScale.size(12), weight: .semibold))
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
                .font(.system(size: RDFontScale.size(11), weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Text(level.shortLabel)
                .font(.system(size: RDFontScale.size(9), weight: .bold))
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
                .font(.system(size: RDFontScale.size(13), weight: .bold))
                .foregroundStyle(Color.rdOnyx)
            Text(RDLocalization.string("onboarding.obtrial.invite.view.su.an.odeme.yok.5ab25673", table: .onboarding, fallback: "Herhangi bir ücret alınmaz."))
                .font(.system(size: RDFontScale.size(15), weight: .semibold))
                .foregroundStyle(Color.rdOnyx)
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 16) {
            footerLink(RDLocalization.string("onboarding.obtrial.invite.view.gizlilik.politikasi.b57b93a6", table: .onboarding, fallback: "Gizlilik Politikası"), action: onPrivacy)
                .accessibilityIdentifier("onboarding.trial_invite.privacy")
            footerLink(RDLocalization.string("onboarding.obtrial.invite.view.geri.yukle.baead888", table: .onboarding, fallback: "Geri Yükle"), action: onRestore)
                .accessibilityIdentifier("onboarding.trial_invite.restore")
            footerLink(RDLocalization.string("onboarding.obtrial.invite.view.sartlar.de56b87b", table: .onboarding, fallback: "Şartlar"), action: onTerms)
                .accessibilityIdentifier("onboarding.trial_invite.terms")
        }
        .font(.system(size: RDFontScale.size(11), weight: .medium))
    }

    private func footerLink(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .foregroundStyle(Color.rdSlate)
                .underline()
        }
        .buttonStyle(.plain)
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
                contextHeadline: RDLocalization.string("onboarding.obtrial.invite.view.uygulamayi.ucretsiz.denemeni.istiyoruz.2cbb5618", table: .onboarding, fallback: "Ücretsiz denemenizi istiyoruz"),
                purchaseError: nil
            )
        )
    }
}

#Preview {
    OBTrialInviteView(onContinue: {})
        .environmentObject(AppState())
}
