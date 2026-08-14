import SwiftUI

// Timeline paywall — trust-building trial flow.
// The screen explains the trial as a time sequence: today, reminder day,
// and billing day. Purchase/restore callbacks stay owned by the flow.
//
// Hooks:
//   onStart   — start trial / purchase
//   onRestore — restore purchases
//   onTerms   — show terms in-app
//   onPrivacy — show privacy in-app
//   onDismiss — close paywall (× button)
//
// Standalone for now; codex will wire to flow + IAP after approval.

private struct TimelineFeatureItem: Hashable {
    let title: String
    let badge: String?

    init(_ title: String, badge: String? = nil) {
        self.title = title
        self.badge = badge
    }
}

struct OBTimelinePaywallView: View {
    var packages: [SubscriptionPlanPackage] = []
    var offeringsLoadState: SubscriptionOfferingsLoadState = .loading
    var isWorking: Bool = false
    var noticeMessage: String?
    let onStart: (OBPlan) -> Void
    let onReloadPackages: () async -> Void
    let onRestore: () -> Void
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onDismiss: () -> Void

    @State private var selectedPlan: OBPlan = .yearly
    @State private var isReloadingPackages = false
    @State private var timelineFlow: Bool = false
    @State private var processingOverlayTitle: String?
    @State private var processingOverlayMessage = RDLocalization.string("onboarding.obtimeline.paywall.view.lutfen.bekleyin.aboneliginiz.app.store.uzerinden.70a7c29c", table: .onboarding, fallback: "Lütfen bekleyin, aboneliğiniz App Store üzerinden kontrol ediliyor.")
    @State private var processingOverlayToken = UUID()

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
                VStack(spacing: 15) {
                    banner
                        .padding(.top, 48)
                        .padding(.bottom, 6)
                        .obStage(delay: 0.02)

                    planToggle
                        .obStage(delay: 0.12)

                    timeline
                        .obStage(delay: 0.12)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, noticeMessage == nil && !isWorking && !isReloadingPackages ? 138 : 182)
            }

            bottomBar
                .frame(maxHeight: .infinity, alignment: .bottom)

            dismissButton
                .padding(.top, 58)
                .padding(.trailing, 18)

            if let processingOverlayTitle {
                PaywallProcessingOverlay(
                    title: processingOverlayTitle,
                    message: processingOverlayMessage
                )
                .transition(.opacity)
                .zIndex(40)
            }
        }
        .onAppear {
            if isWorking {
                startProcessingOverlay()
            }
        }
        .task {
            if packages.isEmpty {
                await reloadPackagesIfNeeded()
            }
        }
        .onChange(of: isWorking) { newValue in
            if newValue {
                startProcessingOverlay()
            } else {
                stopProcessingOverlay()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.timeline_paywall")
    }

    // MARK: - Header

    private var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(paywallTitle)
                    .font(.system(size: RDFontScale.size(30), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
    }

    private var paywallTitle: String {
        selectedPlan == .yearly
            ? RDLocalization.string("onboarding.obtimeline.paywall.view.ucretsiz.deneme.nasil.calisir.030529b1", table: .onboarding, fallback: "Yıllık Plan Nasıl Çalışır")
            : RDLocalization.string("onboarding.obtimeline.paywall.view.plus.aboneligin.gucunu.hemen.kullanin.655cca4a", table: .onboarding, fallback: "Plus Aboneliğin Gücünü Hemen Kullanın")
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            OBPrimaryButton(
                title: primaryButtonTitle,
                trailingIcon: "arrow.right",
                isLoading: isWorking || isReloadingPackages || isWaitingForPrice,
                loadingTitle: isWaitingForPrice || isReloadingPackages ? RDLocalization.string("onboarding.obtimeline.paywall.view.fiyat.yukleniyor.23a52d93", table: .onboarding, fallback: "Fiyat yükleniyor...") : RDLocalization.string("onboarding.obtimeline.paywall.view.satin.alma.hazirlaniyor.7e2cfcb3", table: .onboarding, fallback: "Satın alma hazırlanıyor..."),
                style: .onyx,
                accessibilityID: "onboarding.timeline_paywall.cta"
            ) {
                handlePrimaryAction()
            }
            .disabled(primaryButtonDisabled)
            .opacity(primaryButtonDisabled ? 0.72 : 1)

            Button {
                OBHaptic.soft()
                onDismiss()
            } label: {
                Text(RDLocalization.string("onboarding.obtimeline.paywall.view.simdilik.ucretsiz.devam.et.b59d7d99", table: .onboarding, fallback: "Şimdilik ücretsiz devam et"))
                    .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .underline(true, color: Color.rdSlate.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .opacity(isWorking ? 0.45 : 1)
            .accessibilityLabel(RDLocalization.string("onboarding.obtimeline.paywall.view.simdilik.ucretsiz.devam.et.0aa7a4dc", table: .onboarding, fallback: "Şimdilik ücretsiz devam et"))
            .accessibilityIdentifier("onboarding.timeline_paywall.continue_free")

            if isWorking || isReloadingPackages || noticeMessage != nil {
                paywallNotice
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 14) {
                Button {
                    OBHaptic.light(); onRestore()
                } label: {
                    Text(RDLocalization.string("onboarding.obtimeline.paywall.view.geri.yukle.1fe47fe9", table: .onboarding, fallback: "Geri yükle"))
                        .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                }
                .disabled(isWorking)
                .opacity(isWorking ? 0.55 : 1)
                .accessibilityIdentifier("onboarding.timeline_paywall.restore")

                Circle().fill(Color.rdSlate.opacity(0.35)).frame(width: 3, height: 3)

                Button {
                    OBHaptic.soft(); onTerms()
                } label: {
                    Text(RDLocalization.string("onboarding.obtimeline.paywall.view.kullanim.sartlari.4d6e5995", table: .onboarding, fallback: "Kullanım Şartları"))
                        .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                .disabled(isWorking)
                .accessibilityIdentifier("onboarding.timeline_paywall.terms")

                Circle().fill(Color.rdSlate.opacity(0.35)).frame(width: 3, height: 3)

                Button {
                    OBHaptic.soft(); onPrivacy()
                } label: {
                    Text(RDLocalization.string("onboarding.obtimeline.paywall.view.gizlilik.politikasi.54f451ed", table: .onboarding, fallback: "Gizlilik Politikası"))
                        .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                .disabled(isWorking)
                .accessibilityIdentifier("onboarding.timeline_paywall.privacy")
            }

            Text(priceLine)
                .font(.system(size: RDFontScale.size(11.5), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .accessibilityIdentifier("onboarding.timeline_paywall.price_line")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 6)
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

    private var dismissButton: some View {
        Button {
            OBHaptic.soft()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.94))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .shadow(color: Color.rdBlack.opacity(0.10), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .opacity(isWorking ? 0.45 : 1)
        .accessibilityLabel(RDLocalization.string("onboarding.obtimeline.paywall.view.simdilik.ucretsiz.devam.et.871ae28f", table: .onboarding, fallback: "Şimdilik ücretsiz devam et"))
        .accessibilityIdentifier("onboarding.timeline_paywall.dismiss")
    }

    @ViewBuilder
    private var paywallNotice: some View {
        HStack(spacing: 8) {
            if isWorking || isReloadingPackages {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.rdBlack)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: RDFontScale.size(12), weight: .semibold))
                    .foregroundStyle(Color.rdHigh)
            }

            Text(noticeText)
                .font(.system(size: RDFontScale.size(11.5), weight: .semibold, design: .rounded))
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

    private func startProcessingOverlay() {
        let token = UUID()
        processingOverlayToken = token
        processingOverlayTitle = RDLocalization.string("onboarding.obtimeline.paywall.view.app.store.odeme.ekrani.aciliyor.af128c75", table: .onboarding, fallback: "App Store ödeme ekranı açılıyor...")
        processingOverlayMessage = RDLocalization.string("onboarding.obtimeline.paywall.view.onay.penceresi.acildiginda.islemi.app.store.uzer.195dca6a", table: .onboarding, fallback: "Onay penceresi açıldığında işlemi App Store üzerinden tamamlayabilirsin.")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard isWorking, processingOverlayToken == token, processingOverlayTitle != nil else { return }
            processingOverlayTitle = RDLocalization.string("onboarding.obtimeline.paywall.view.satin.alma.dogrulaniyor.4ccbcf49", table: .onboarding, fallback: "Satın alma doğrulanıyor")
            processingOverlayMessage = RDLocalization.string("onboarding.obtimeline.paywall.view.lutfen.bekleyin.aboneliginiz.app.store.uzerinden.34bd6c86", table: .onboarding, fallback: "Lütfen bekleyin, aboneliğiniz App Store üzerinden kontrol ediliyor.")
        }
    }

    private func stopProcessingOverlay() {
        processingOverlayToken = UUID()
        processingOverlayTitle = nil
    }

    private var primaryButtonTitle: String {
        guard selectedPackage != nil else {
            return priceLoadError == nil ? RDLocalization.string("onboarding.obtimeline.paywall.view.fiyat.yukleniyor.31966e06", table: .onboarding, fallback: "Fiyat yükleniyor...") : RDLocalization.string("onboarding.obtimeline.paywall.view.tekrar.dene.f8ced812", table: .onboarding, fallback: "Tekrar dene")
        }
        return selectedPlan == .yearly ? RDLocalization.string("onboarding.obtimeline.paywall.view.ucretsiz.denemeyi.baslat.dc125184", table: .onboarding, fallback: "Devam et") : RDLocalization.string("onboarding.obtimeline.paywall.view.aboneligi.baslat.79fd5050", table: .onboarding, fallback: "Aboneliği başlat")
    }

    private var primaryButtonDisabled: Bool {
        isWorking || isReloadingPackages || (selectedPackage == nil && priceLoadError == nil)
    }

    private var isWaitingForPrice: Bool {
        selectedPackage == nil && offeringsLoadState.isLoading
    }

    private var noticeText: String {
        if isWorking { return RDLocalization.string("onboarding.obtimeline.paywall.view.app.store.satin.alma.ekrani.hazirlaniyor.b11a0512", table: .onboarding, fallback: "App Store satın alma ekranı hazırlanıyor...") }
        if isReloadingPackages { return RDLocalization.string("onboarding.obtimeline.paywall.view.app.store.fiyatlari.yukleniyor.4a75e8db", table: .onboarding, fallback: "App Store fiyatları yükleniyor...") }
        return noticeMessage ?? ""
    }

    private var priceLoadError: String? {
        guard selectedPackage == nil else { return nil }
        switch offeringsLoadState {
        case .loading, .retryingOnce:
            return nil
        case .loaded:
            return RDLocalization.string("onboarding.obtimeline.paywall.view.app.store.fiyati.su.an.alinamadi.internet.baglan.d59116a9", table: .onboarding, fallback: "App Store fiyatı şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene.")
        case let .failed(message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? RDLocalization.string("onboarding.obtimeline.paywall.view.app.store.fiyati.su.an.alinamadi.internet.baglan.3beb566f", table: .onboarding, fallback: "App Store fiyatı şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene.")
                : trimmed
        }
    }

    private var priceStatusLine: String {
        priceLoadError == nil ? OBTrialPriceCopy.loadingPrice : OBTrialPriceCopy.unavailablePrice
    }

    private var selectedPackage: SubscriptionPlanPackage? {
        plusPackage(for: selectedPlan).flatMap { $0.displayPrice == nil ? nil : $0 }
    }

    private func handlePrimaryAction() {
        guard !isWorking, !isReloadingPackages else { return }
        guard selectedPackage != nil else {
            reloadPackages()
            return
        }
        onStart(selectedPlan)
    }

    private func reloadPackages() {
        Task {
            await reloadPackagesIfNeeded()
        }
    }

    private func reloadPackagesIfNeeded() async {
        guard !isWorking, !isReloadingPackages else { return }
        isReloadingPackages = true
        await onReloadPackages()
        isReloadingPackages = false
    }

    // MARK: - Plan toggle

    private var planToggle: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                planPill(.yearly, label: RDLocalization.string("onboarding.obtimeline.paywall.view.yillik.889fc7f2", table: .onboarding, fallback: "Yıllık"))
                planPill(.monthly, label: RDLocalization.string("onboarding.obtimeline.paywall.view.aylik.311fbe87", table: .onboarding, fallback: "Aylık"))
            }
            .padding(4)
            .background(Color.rdFog)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.rdLine, lineWidth: 1))
            .frame(width: 210)

            if selectedPlan == .yearly {
                Text(RDLocalization.string("onboarding.obtimeline.paywall.view.17.indirim.16d1d18a", table: .onboarding, fallback: "%17 İndirim"))
                    .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
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
                .font(.system(size: RDFontScale.size(11.5), weight: .bold, design: .rounded))
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

    private var plusFeatureItems: [TimelineFeatureItem] {
        [
            TimelineFeatureItem(RDLocalization.string("onboarding.obtimeline.paywall.view.detayli.analiz.24351d3b", table: .onboarding, fallback: "Detaylı Analiz")),
            TimelineFeatureItem(RDLocalization.string("onboarding.obtimeline.paywall.view.risk.analizi.fine.kinney.ve.5.5.b43a3cfb", table: .onboarding, fallback: "Risk Analizi (Fine-Kinney ve 5*5)")),
            TimelineFeatureItem(RDLocalization.string("onboarding.obtimeline.paywall.view.pdf.excel.rapor.95bfded2", table: .onboarding, fallback: "PDF/Excel Rapor")),
            TimelineFeatureItem(RDLocalization.string("onboarding.obtimeline.paywall.view.firma.yonetimi.3eeadbe7", table: .onboarding, fallback: "Firma Yönetimi")),
            TimelineFeatureItem(RDLocalization.string("onboarding.obtimeline.paywall.view.coklu.fotograf.analizi.3c6f6a3d", table: .onboarding, fallback: "Çoklu Fotoğraf Analizi"), badge: "Yeni"),
            TimelineFeatureItem(RDLocalization.string("onboarding.obtimeline.paywall.view.sektor.bazli.analiz.f645149d", table: .onboarding, fallback: "Sektör Bazlı Analiz"))
        ]
    }

    private var yearlyTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineStep(
                index: 0,
                icon: "lock.shield.fill",
                accent: Color.rdGreen,
                day: RDLocalization.string("onboarding.obtimeline.paywall.view.bugun.48c76375", table: .onboarding, fallback: "Bugün"),
                detail: RDLocalization.string("onboarding.obtimeline.paywall.view.plus.ozellikleri.acilir.ucret.alinmaz.c93f0f8d", table: .onboarding, fallback: "Yıllık Plus özelliklerini ve App Store fiyatını incele."),
                featureItems: plusFeatureItems,
                isLast: false
            )
            timelineStep(
                index: 1,
                icon: "bell.fill",
                accent: Color(hex: "#F0A400"),
                day: RDLocalization.string("onboarding.obtimeline.paywall.view.5.gun.a1306735", table: .onboarding, fallback: "App Store"),
                detail: RDLocalization.string("onboarding.obtimeline.paywall.view.denemen.bitmeden.sana.hatirlatma.gondeririz.cc0144c2", table: .onboarding, fallback: "Fiyatı ve varsa uygun teklifi App Store onay ekranında doğrula."),
                isLast: false
            )
            timelineStep(
                index: 2,
                icon: "crown.fill",
                accent: Color(hex: "#F0A400"),
                day: RDLocalization.string("onboarding.obtimeline.paywall.view.7.gun.5bf94fa7", table: .onboarding, fallback: "Yenileme"),
                detail: RDLocalization.string("onboarding.obtimeline.paywall.view.devam.edersen.yillik.plan.baslar.istedigin.zaman.68e836a8", table: .onboarding, fallback: "Onaylanan plan App Store şartlarıyla yenilenir; istediğin zaman iptal edebilirsin."),
                isLast: true
            )
        }
        .padding(14)
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
                day: RDLocalization.string("onboarding.obtimeline.paywall.view.bugun.21298096", table: .onboarding, fallback: "Bugün"),
                detail: RDLocalization.string("onboarding.obtimeline.paywall.view.tum.ozellikler.hemen.aktif.olur.odeme.baslar.b6ba3101", table: .onboarding, fallback: "Tüm özellikler hemen aktif olur, ödeme başlar."),
                featureItems: plusFeatureItems,
                isLast: false
            )
            timelineStep(
                index: 1,
                icon: "calendar.badge.checkmark",
                accent: Color.rdGreen,
                day: RDLocalization.string("onboarding.obtimeline.paywall.view.her.ay.e9db7612", table: .onboarding, fallback: "Her ay"),
                detail: monthlyRenewalLine,
                isLast: true
            )
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .rdCardShadow()
    }

    private var yearlyPrice: String {
        displayPrice(for: .yearly) ?? priceStatusLine
    }

    private var monthlyPrice: String {
        displayPrice(for: .monthly) ?? priceStatusLine
    }

    private var yearlyMonthlyEquivalent: String? {
        guard let monthlyEquivalent = plusPackage(for: .yearly)?.displayMonthlyEquivalentPrice else { return nil }
        return monthlyEquivalent.hasSuffix("/ay") ? monthlyEquivalent : "\(monthlyEquivalent)/ay"
    }

    private var yearlyPaywallLine: String {
        guard let price = displayPrice(for: .yearly) else { return priceStatusLine }
        guard let yearlyMonthlyEquivalent else { return RDLocalization.format("onboarding.obtimeline.paywall.view.7.gun.ucretsiz.sonra.1.1c216e89", table: .onboarding, fallback: "Yıllık %1$@ · varsa teklif App Store'da uygulanır", arguments: [String(describing: price)]) }
        return RDLocalization.format("onboarding.obtimeline.paywall.view.7.gun.ucretsiz.sonra.1.2.55ea6bc2", table: .onboarding, fallback: "Yıllık %1$@ (%2$@) · varsa teklif App Store'da uygulanır", arguments: [String(describing: price), String(describing: yearlyMonthlyEquivalent)])
    }

    private var monthlyPaywallLine: String {
        guard let price = displayPrice(for: .monthly) else { return priceStatusLine }
        return RDLocalization.format("onboarding.obtimeline.paywall.view.1.ay.istedigin.zaman.iptal.b6b0b4af", table: .onboarding, fallback: "%1$@/ay — istediğin zaman iptal", arguments: [String(describing: price)])
    }

    private var monthlyRenewalLine: String {
        guard let price = displayPrice(for: .monthly) else { return RDLocalization.string("onboarding.obtimeline.paywall.view.aylik.fiyat.app.store.uzerinden.yuklenecek.1c047937", table: .onboarding, fallback: "Aylık fiyat App Store üzerinden yüklenecek.") }
        return RDLocalization.format("onboarding.obtimeline.paywall.view.1.otomatik.yenilenir.istedigin.zaman.iptal.edebi.14f7048e", table: .onboarding, fallback: "%1$@ otomatik yenilenir. İstediğin zaman iptal edebilirsin.", arguments: [String(describing: price)])
    }

    private func displayPrice(for plan: OBPlan) -> String? {
        plusPackage(for: plan)?.displayPrice
    }

    private func plusPackage(for plan: OBPlan) -> SubscriptionPlanPackage? {
        packages
            .filter { $0.tier == .plus }
            .first { $0.matchesOnboardingBilling(plan) }
    }

    private func timelineStep(
        index: Int,
        icon: String,
        accent: Color,
        day: String,
        detail: String,
        featureItems: [TimelineFeatureItem] = [],
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(accent, lineWidth: 1.6)
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: RDFontScale.size(15), weight: .semibold))
                        .foregroundStyle(accent)
                }

                if !isLast {
                    timelineConnector(
                        accent: accent,
                        height: timelineConnectorHeight(featureItemCount: featureItems.count)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(day)
                    .font(.system(size: RDFontScale.size(15), weight: .semibold))
                    .foregroundStyle(Color.rdOnyx)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: RDFontScale.size(12.2), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !featureItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(featureItems, id: \.self) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: RDFontScale.size(11), weight: .bold))
                                    .foregroundStyle(Color.rdGreen)
                                Text(item.title)
                                    .font(.system(size: RDFontScale.size(11.4), weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.rdBlack)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let badge = item.badge {
                                    Text(badge)
                                        .font(.system(size: RDFontScale.size(8.2), weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.rdGreen)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.rdGreen.opacity(0.10))
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.rdGreen.opacity(0.20), lineWidth: 0.8)
                                        )
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : 10)
        }
        .obStage(delay: 0.24 + Double(index) * 0.08)
        .onAppear { startTimelineFlow() }
    }

    private func timelineConnectorHeight(featureItemCount: Int) -> CGFloat {
        guard featureItemCount > 0 else { return 50 }
        return 102 + CGFloat(max(0, featureItemCount - 3)) * 19
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
        onReloadPackages: {},
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
