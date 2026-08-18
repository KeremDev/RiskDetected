import SwiftUI

/// Claude Design paywall akışı: PLUS ve PRO ekranlarını yönetir, RevenueCat
/// paketlerini bağlar, satın alma / geri yükleme / hukuki metin akışlarını ve
/// paywall funnel loglarını yürütür.
///
/// Uygulamadaki tüm paywall giriş noktaları (in-app yükseltme ve onboarding
/// 11. adım) bu görünümü kullanır.
struct PaywallDesignFlowView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    var source: PaywallSource = .inApp
    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String?

    @State private var screenOverride: InAppPaywallScreen?
    @State private var plusBilling: InAppPaywallBilling = .yearly
    @State private var proBilling: InAppPaywallBilling = .yearly
    @State private var isWorking = false
    @State private var workingMessage: String?
    @State private var errorMessage: String?
    @State private var funnelSessionID = UUID()
    @State private var didLogView = false
    @State private var selectedLegalDocument: LegalDocumentKind?
    @State private var processingOverlayTitle: String?
    @State private var processingOverlayMessage = RDLocalization.string("paywall.in.app.paywall.view.lutfen.bekleyin.aboneliginiz.app.store.uzerinden.1e66715b", table: .paywall, fallback: "Lütfen bekleyin, aboneliğiniz App Store üzerinden kontrol ediliyor.")
    @State private var processingOverlayToken = UUID()

    private let variantID = "claude_design_paywall_v1"
    private let manageSubscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    // MARK: - Ekran seçimi

    private var activeScreen: InAppPaywallScreen {
        #if DEBUG
        if Self.isUITestForceProPaywall {
            return .pro
        }
        #endif
        if source == .onboardingV2 {
            return screenOverride ?? .plus
        }
        return screenOverride ?? (app.currentTier == .free ? .plus : .pro)
    }

    private var activeBilling: InAppPaywallBilling {
        billing(for: activeScreen)
    }

    var body: some View {
        ZStack {
            PaywallDesignScreen(
                screen: activeScreen,
                heroLabel: heroLabel,
                tierName: activeScreen.tier.title,
                accent: accent,
                selectedBackground: selectedBackground,
                showsTrialTimeline: trialDays != nil,
                trialDays: trialDays ?? 7,
                timelineFeatures: PaywallDesignCopy.timelineFeatures,
                comparisonLeft: comparisonColumns.left,
                comparisonRight: comparisonColumns.right,
                comparisonRows: comparisonRows,
                annual: planOption(for: .yearly),
                monthly: planOption(for: .monthly),
                selectedBilling: activeBilling,
                cta: ctaState,
                notice: workingMessage ?? notice,
                errorMessage: visibleError,
                crossSell: crossSell,
                onClose: closePaywall,
                onSelectBilling: select(billing:),
                onCTA: handlePrimaryAction,
                onRestore: restore,
                onTerms: { selectedLegalDocument = .terms },
                onPrivacy: { selectedLegalDocument = .privacy },
                onManageSubscription: { openURL(manageSubscriptionURL) },
                onCrossSell: toggleScreen
            )

            if let processingOverlayTitle {
                PaywallProcessingOverlay(
                    title: processingOverlayTitle,
                    message: processingOverlayMessage
                )
                .transition(.opacity)
                .zIndex(40)
            }
        }
        .task {
            logPaywallViewIfNeeded()
            await app.refreshSubscriptionOfferings()
            alignBillingWithAvailablePackage()
        }
        .sheet(item: $selectedLegalDocument) { kind in
            LegalInfoSheet(initialDocument: kind) {
                selectedLegalDocument = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.light)
        }
        .onChange(of: app.subscriptionPackages) { _ in
            alignBillingWithAvailablePackage()
        }
    }

    // MARK: - Görünüm verisi

    private var accent: Color {
        activeScreen == .plus ? PaywallDesignColor.orange : PaywallDesignColor.green
    }

    private var selectedBackground: Color {
        activeScreen == .plus ? PaywallDesignColor.orangeCardBg : PaywallDesignColor.greenCardBg
    }

    /// App Store'da tanımlı ücretsiz deneme gün sayısı. Teklif yoksa nil olur ve
    /// ekran deneme anlatımı yerine karşılaştırma tablosunu gösterir.
    private var trialDays: Int? {
        guard activeScreen == .plus else { return nil }
        return selectedPackage(for: .plus, billing: .yearly)?.introductoryFreeTrialDays
    }

    private var heroLabel: String {
        if activeScreen == .plus, trialDays != nil, activeBilling == .yearly {
            return RDLocalization.string(
                "paywall.design.hero.trial_headline",
                table: .paywall,
                fallback: "Ücretsiz Deneme Nasıl Çalışır?"
            )
        }
        return RDLocalization.format(
            "paywall.design.hero.benefits_format",
            table: .paywall,
            fallback: "%1$@ Abonelik Avantajları",
            arguments: [activeScreen.tier.title]
        )
    }

    private var comparisonColumns: (left: PaywallDesignComparisonTable.Column, right: PaywallDesignComparisonTable.Column) {
        switch activeScreen {
        case .plus:
            return (
                PaywallDesignComparisonTable.Column(
                    title: SubscriptionTier.free.title,
                    color: PaywallDesignColor.muted,
                    weight: .semibold
                ),
                PaywallDesignComparisonTable.Column(
                    title: SubscriptionTier.plus.title,
                    color: PaywallDesignColor.orange,
                    weight: .bold
                )
            )
        case .pro:
            return (
                PaywallDesignComparisonTable.Column(
                    title: SubscriptionTier.plus.title,
                    color: PaywallDesignColor.orange,
                    weight: .semibold
                ),
                PaywallDesignComparisonTable.Column(
                    title: SubscriptionTier.pro.title,
                    color: PaywallDesignColor.green,
                    weight: .bold
                )
            )
        }
    }

    private var comparisonRows: [PaywallDesignComparisonRow] {
        switch activeScreen {
        case .plus: return PaywallDesignCopy.freeVersusPlusRows
        case .pro: return PaywallDesignCopy.plusVersusProRows
        }
    }

    private var crossSell: PaywallDesignCrossSell? {
        switch activeScreen {
        case .plus:
            return PaywallDesignCrossSell(
                style: .pro,
                prefix: RDLocalization.string(
                    "paywall.design.cross_sell.pro.prefix",
                    table: .paywall,
                    fallback: "Daha gelişmiş ve sınırsız özellikler için "
                ),
                highlight: SubscriptionTier.pro.title,
                suffix: RDLocalization.string(
                    "paywall.design.cross_sell.pro.suffix",
                    table: .paywall,
                    fallback: " üyeliğimizi inceleyin"
                ),
                accessibilityIdentifier: "in_app_paywall.plus.pro_link"
            )
        case .pro:
            return PaywallDesignCrossSell(
                style: .plus,
                prefix: RDLocalization.string(
                    "paywall.design.cross_sell.plus.prefix",
                    table: .paywall,
                    fallback: "Temel özellikler için "
                ),
                highlight: SubscriptionTier.plus.title,
                suffix: RDLocalization.string(
                    "paywall.design.cross_sell.plus.suffix",
                    table: .paywall,
                    fallback: " üyeliğimizi inceleyin"
                ),
                accessibilityIdentifier: "in_app_paywall.pro.plus_link"
            )
        }
    }

    private func planOption(for billing: InAppPaywallBilling) -> PaywallDesignPlanOption {
        let package = selectedPackage(for: activeScreen, billing: billing)
        let price = package?.displayPrice ?? unavailablePriceText

        switch billing {
        case .yearly:
            let monthlyEquivalent = package?.displayMonthlyEquivalentPrice
            return PaywallDesignPlanOption(
                title: InAppPaywallBilling.yearly.title,
                price: price,
                caption: monthlyEquivalent.map {
                    RDLocalization.format(
                        "paywall.design.plan.per_month_format",
                        table: .paywall,
                        fallback: "%1$@ / Ay",
                        arguments: [$0]
                    )
                } ?? RDLocalization.string(
                    "paywall.design.plan.yearly_caption",
                    table: .paywall,
                    fallback: "/ Yıl"
                ),
                trialNote: trialNoteText,
                badgeLabel: RDLocalization.string(
                    "paywall.design.plan.badge.popular",
                    table: .paywall,
                    fallback: "Popüler"
                ),
                badgeDiscount: discountText
            )
        case .monthly:
            return PaywallDesignPlanOption(
                title: InAppPaywallBilling.monthly.title,
                price: price,
                caption: RDLocalization.string(
                    "paywall.design.plan.monthly_caption",
                    table: .paywall,
                    fallback: "/ Ay"
                ),
                trialNote: nil,
                badgeLabel: nil,
                badgeDiscount: nil
            )
        }
    }

    private var trialNoteText: String? {
        guard let trialDays else { return nil }
        return RDLocalization.format(
            "paywall.design.plan.trial_note_format",
            table: .paywall,
            fallback: "%1$@ gün ücretsiz",
            arguments: [String(trialDays)]
        )
    }

    /// Yıllık paketin aylık pakete göre gerçek indirim oranı. App Store fiyatları
    /// yüklenmemişse veya fark anlamlı değilse rozet gösterilmez.
    private var discountText: String? {
        guard
            let annual = selectedPackage(for: activeScreen, billing: .yearly)?.priceAmount,
            let monthly = selectedPackage(for: activeScreen, billing: .monthly)?.priceAmount,
            monthly > 0
        else { return nil }

        let fullYearPrice = monthly * 12
        guard fullYearPrice > annual else { return nil }

        let ratio = NSDecimalNumber(decimal: (fullYearPrice - annual) / fullYearPrice).doubleValue
        let percent = Int((ratio * 100).rounded())
        guard percent >= 5 else { return nil }

        return RDLocalization.format(
            "paywall.design.plan.discount_format",
            table: .paywall,
            fallback: "%%%1$@ İndirim",
            arguments: [String(percent)]
        )
    }

    private var ctaState: PaywallDesignCTAState {
        PaywallDesignCTAState(
            title: primaryButtonTitle,
            isLoading: isWorking,
            isDisabled: primaryButtonDisabled,
            accessibilityIdentifier: "in_app_paywall.cta"
        )
    }

    private var primaryButtonTitle: String {
        if isWorking {
            return RDLocalization.string("paywall.in.app.paywall.view.satin.alma.hazirlaniyor.7db69bb8", table: .paywall, fallback: "Satın alma hazırlanıyor...")
        }
        if currentPlanIncludesActiveScreen {
            return RDLocalization.string("paywall.in.app.paywall.view.planin.aktif.a449054e", table: .paywall, fallback: "Planın aktif")
        }
        if selectedPackage == nil {
            return packageLoadError == nil
                ? RDLocalization.string("paywall.in.app.paywall.view.fiyat.yukleniyor.9767cab5", table: .paywall, fallback: "Fiyat yükleniyor...")
                : RDLocalization.string("paywall.in.app.paywall.view.tekrar.dene.a5447e51", table: .paywall, fallback: "Tekrar dene")
        }
        if activeScreen == .plus, activeBilling == .yearly, trialDays != nil {
            return RDLocalization.string("paywall.design.cta.start_trial", table: .paywall, fallback: "Ücretsiz Denemeyi Başlat")
        }
        return RDLocalization.string("paywall.in.app.paywall.view.aboneligi.baslat.229585df", table: .paywall, fallback: "Aboneliği Başlat")
    }

    private var primaryButtonDisabled: Bool {
        isWorking ||
            currentPlanIncludesActiveScreen ||
            (selectedPackage == nil && packageLoadError == nil)
    }

    private var currentPlanIncludesActiveScreen: Bool {
        app.currentTier.isPaid && app.currentTier.includes(activeScreen.tier)
    }

    private var visibleError: String? {
        errorMessage ?? packageLoadError
    }

    private var selectedPackage: SubscriptionPlanPackage? {
        selectedPackage(for: activeScreen, billing: activeBilling)
    }

    private var packageLoadError: String? {
        guard selectedPackage == nil else { return nil }
        switch app.subscriptionOfferingsLoadState {
        case .loading, .retryingOnce:
            return nil
        case .loaded:
            return RDLocalization.string("paywall.in.app.paywall.view.secili.abonelik.paketi.veya.app.store.fiyati.su..8fe2c5f0", table: .paywall, fallback: "Seçili abonelik paketi veya App Store fiyatı şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene.")
        case let .failed(message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? RDLocalization.string("paywall.in.app.paywall.view.app.store.abonelik.fiyatlari.su.an.alinamadi.int.7a4731b3", table: .paywall, fallback: "App Store abonelik fiyatları şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene.")
                : trimmed
        }
    }

    private var unavailablePriceText: String {
        packageLoadError == nil
            ? RDLocalization.string("paywall.in.app.paywall.view.fiyat.yukleniyor.91a8a0da", table: .paywall, fallback: "fiyat yükleniyor")
            : RDLocalization.string("paywall.in.app.paywall.view.fiyat.alinamadi.50d6ae8c", table: .paywall, fallback: "fiyat alınamadı")
    }

    // MARK: - Etkileşimler

    private func select(billing newValue: InAppPaywallBilling) {
        guard !isWorking else { return }
        let screen = activeScreen
        guard billing(for: screen) != newValue else { return }
        switch screen {
        case .plus: plusBilling = newValue
        case .pro: proBilling = newValue
        }
        UISelectionFeedbackGenerator().selectionChanged()
        logPaywallEvent(.billingSelect, screen: screen, billing: newValue)
    }

    private func toggleScreen() {
        let target: InAppPaywallScreen = activeScreen == .plus ? .pro : .plus
        guard !isWorking else { return }
        switch target {
        case .plus: plusBilling = .yearly
        case .pro: proBilling = .yearly
        }
        screenOverride = target
        errorMessage = nil
        UISelectionFeedbackGenerator().selectionChanged()
        logPaywallEvent(.planSelect, screen: target, billing: billing(for: target))
    }

    private func billing(for screen: InAppPaywallScreen) -> InAppPaywallBilling {
        switch screen {
        case .plus: return plusBilling
        case .pro: return proBilling
        }
    }

    private func closePaywall() {
        logPaywallEvent(.close)
        onClose()
    }

    private func handlePrimaryAction() {
        guard !isWorking else { return }
        logPaywallEvent(.ctaTap)
        if selectedPackage == nil {
            reloadPackages()
            return
        }
        purchaseSelectedPlan()
    }

    private func reloadPackages() {
        guard !isWorking else { return }
        isWorking = true
        stopProcessingOverlay()
        workingMessage = RDLocalization.string("paywall.in.app.paywall.view.app.store.abonelik.paketleri.yukleniyor.a764aab2", table: .paywall, fallback: "App Store abonelik paketleri yükleniyor...")
        errorMessage = nil
        Task {
            await app.refreshSubscriptionOfferings()
            alignBillingWithAvailablePackage()
            workingMessage = nil
            isWorking = false
        }
    }

    private func purchaseSelectedPlan() {
        let purchaseScreen = activeScreen
        let purchaseBilling = billing(for: purchaseScreen)

        guard let package = selectedPackage(for: purchaseScreen, billing: purchaseBilling) else {
            errorMessage = RDLocalization.string("paywall.in.app.paywall.view.bu.plan.icin.app.store.paketi.henuz.yuklenmedi.3c3253d4", table: .paywall, fallback: "Bu plan için App Store paketi henüz yüklenmedi.")
            return
        }

        isWorking = true
        startProcessingOverlay(
            initialTitle: RDLocalization.string("paywall.in.app.paywall.view.app.store.odeme.ekrani.aciliyor.2017db3c", table: .paywall, fallback: "App Store ödeme ekranı açılıyor..."),
            initialMessage: RDLocalization.string("paywall.in.app.paywall.view.onay.penceresi.acildiginda.islemi.app.store.uzer.9eb4daac", table: .paywall, fallback: "Onay penceresi açıldığında işlemi App Store üzerinden tamamlayabilirsin."),
            delayedTitle: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulaniyor.88f1450c", table: .paywall, fallback: "Satın alma doğrulanıyor"),
            delayedMessage: RDLocalization.string("paywall.in.app.paywall.view.lutfen.bekleyin.aboneliginiz.app.store.uzerinden.a404ac62", table: .paywall, fallback: "Lütfen bekleyin, aboneliğiniz App Store üzerinden kontrol ediliyor."),
            delayedWorkingMessage: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulaniyor.167f9bd5", table: .paywall, fallback: "Satın alma doğrulanıyor...")
        )
        workingMessage = RDLocalization.string("paywall.in.app.paywall.view.app.store.odeme.ekrani.aciliyor.ea863cb0", table: .paywall, fallback: "App Store ödeme ekranı açılıyor...")
        errorMessage = nil
        logPaywallEvent(.purchaseStarted, screen: purchaseScreen, billing: purchaseBilling)

        Task {
            do {
                let purchasedState = try await app.purchaseSubscription(
                    packageID: package.id,
                    expectedTier: purchaseScreen.tier
                )
                await app.refreshPlanState()
                stopProcessingOverlay()
                workingMessage = nil
                isWorking = false

                if purchasedState.tier == purchaseScreen.tier {
                    logPaywallEvent(.purchaseSucceeded, screen: purchaseScreen, billing: purchaseBilling)
                    onSubscribe()
                } else {
                    errorMessage = RDLocalization.format("paywall.in.app.paywall.view.abonelik.dogrulanamadi.secilen.plan.1.dogrulanan.715caf2d", table: .paywall, fallback: "Abonelik doğrulanamadı. Seçilen plan %1$@, doğrulanan plan %2$@.", arguments: [String(describing: purchaseScreen.tier.title), String(describing: purchasedState.tier.title)])
                    logPaywallEvent(
                        .purchaseFailed,
                        screen: purchaseScreen,
                        billing: purchaseBilling,
                        purchaseError: errorMessage
                    )
                }
            } catch is CancellationError {
                stopProcessingOverlay()
                workingMessage = nil
                isWorking = false
            } catch {
                stopProcessingOverlay()
                workingMessage = nil
                isWorking = false
                let classification = PurchaseErrorClassifier.classify(error)
                errorMessage = AppErrorMessage.makePurchase(
                    classification: classification,
                    context: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulanamadi.f72c702f", table: .paywall, fallback: "Satın alma doğrulanamadı"),
                    fallbackTitle: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulanamadi.2601825b", table: .paywall, fallback: "Satın alma doğrulanamadı")
                ).message
                logPaywallEvent(
                    .purchaseFailed,
                    screen: purchaseScreen,
                    billing: purchaseBilling,
                    purchaseError: errorMessage
                )
            }
        }
    }

    private func restore() {
        guard !isWorking else { return }
        isWorking = true
        startProcessingOverlay(
            initialTitle: RDLocalization.string("paywall.in.app.paywall.view.satin.alimlar.kontrol.ediliyor.74b29de4", table: .paywall, fallback: "Satın alımlar kontrol ediliyor..."),
            initialMessage: RDLocalization.string("paywall.in.app.paywall.view.app.store.hesabindaki.abonelik.kayitlari.kontrol.33625ca8", table: .paywall, fallback: "App Store hesabındaki abonelik kayıtları kontrol ediliyor."),
            delayedTitle: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulaniyor.4b3902cb", table: .paywall, fallback: "Satın alma doğrulanıyor"),
            delayedMessage: RDLocalization.string("paywall.in.app.paywall.view.lutfen.bekleyin.aboneliginiz.app.store.uzerinden.ddd7a8ea", table: .paywall, fallback: "Lütfen bekleyin, aboneliğiniz App Store üzerinden kontrol ediliyor."),
            delayedWorkingMessage: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulaniyor.f4be1a8a", table: .paywall, fallback: "Satın alma doğrulanıyor...")
        )
        workingMessage = RDLocalization.string("paywall.in.app.paywall.view.app.store.satin.alimlarin.kontrol.ediliyor.cd3aaf32", table: .paywall, fallback: "App Store satın alımların kontrol ediliyor...")
        errorMessage = nil
        logPaywallEvent(.restoreTap)

        Task {
            do {
                let restoredState = try await app.restoreSubscriptions()
                stopProcessingOverlay()
                workingMessage = nil
                isWorking = false
                if restoredState.tier.isPaid {
                    onSubscribe()
                } else {
                    errorMessage = RDLocalization.string("paywall.in.app.paywall.view.geri.yuklenecek.aktif.abonelik.bulunamadi.ebe10a3d", table: .paywall, fallback: "Geri yüklenecek aktif abonelik bulunamadı.")
                }
            } catch {
                stopProcessingOverlay()
                workingMessage = nil
                isWorking = false
                errorMessage = AppErrorMessage.makePurchase(
                    error,
                    context: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulanamadi.08b97e50", table: .paywall, fallback: "Satın alma doğrulanamadı"),
                    fallbackTitle: RDLocalization.string("paywall.in.app.paywall.view.satin.alma.dogrulanamadi.e9d10258", table: .paywall, fallback: "Satın alma doğrulanamadı")
                ).message
            }
        }
    }

    // MARK: - İşlem katmanı

    private func startProcessingOverlay(
        initialTitle: String,
        initialMessage: String,
        delayedTitle: String,
        delayedMessage: String,
        delayedWorkingMessage: String
    ) {
        let token = UUID()
        processingOverlayToken = token
        processingOverlayTitle = initialTitle
        processingOverlayMessage = initialMessage

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard isWorking, processingOverlayToken == token, processingOverlayTitle != nil else { return }
            processingOverlayTitle = delayedTitle
            processingOverlayMessage = delayedMessage
            workingMessage = delayedWorkingMessage
        }
    }

    private func stopProcessingOverlay() {
        processingOverlayToken = UUID()
        processingOverlayTitle = nil
    }

    private func alignBillingWithAvailablePackage() {
        alignBilling(for: .plus)
        alignBilling(for: .pro)
    }

    private func alignBilling(for screen: InAppPaywallScreen) {
        let currentBilling = billing(for: screen)
        guard selectedPackage(for: screen, billing: currentBilling) == nil else { return }

        if selectedPackage(for: screen, billing: .yearly) != nil {
            switch screen {
            case .plus: plusBilling = .yearly
            case .pro: proBilling = .yearly
            }
        } else if selectedPackage(for: screen, billing: .monthly) != nil {
            switch screen {
            case .plus: plusBilling = .monthly
            case .pro: proBilling = .monthly
            }
        }
    }

    private func selectedPackage(
        for screen: InAppPaywallScreen,
        billing: InAppPaywallBilling
    ) -> SubscriptionPlanPackage? {
        app.subscriptionPackages
            .filter { $0.tier == screen.tier }
            .first { $0.matchesDesignPaywall(billing) && $0.displayPrice != nil }
    }

    // MARK: - Funnel logları

    private func logPaywallViewIfNeeded() {
        guard !didLogView else { return }
        didLogView = true
        logPaywallEvent(.view)
    }

    private func logPaywallEvent(
        _ event: PaywallEventName,
        screen: InAppPaywallScreen? = nil,
        billing: InAppPaywallBilling? = nil,
        purchaseError: String? = nil
    ) {
        let loggedScreen = screen ?? activeScreen
        let loggedBilling = billing ?? self.billing(for: loggedScreen)
        let package = selectedPackage(for: loggedScreen, billing: loggedBilling)

        PaywallEventService.shared.record(
            event,
            funnelSessionID: funnelSessionID,
            source: source,
            variantID: variantID,
            segmentKey: nil,
            selectedTier: loggedScreen.tier,
            billing: loggedBilling.rawValue,
            productIdentifier: package?.productIdentifier,
            metadata: PaywallEventMetadata(
                layout: loggedScreen.analyticsValue,
                currentTier: app.currentTier.rawValue,
                selectedPackageID: package?.id,
                noticePresent: notice != nil,
                errorMessage: errorMessage,
                contextHeadline: nil,
                purchaseError: purchaseError
            )
        )
    }

    #if DEBUG
    private static var isUITestForceProPaywall: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_FORCE_PRO_PAYWALL")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_FORCE_PRO_PAYWALL"] == "1"
    }
    #endif
}

// MARK: - Sabit içerik

enum PaywallDesignCopy {
    static var timelineFeatures: [String] {
        [
            RDLocalization.string("paywall.in.app.paywall.view.risk.analizi.61b95913", table: .paywall, fallback: "Risk Analizi"),
            RDLocalization.string("paywall.in.app.paywall.view.detayli.analiz.e955c96b", table: .paywall, fallback: "Detaylı analiz"),
            RDLocalization.string("paywall.in.app.paywall.view.coklu.fotograf.analizi.c5d7318b", table: .paywall, fallback: "Çoklu Fotoğraf Analizi"),
            RDLocalization.string("paywall.in.app.paywall.view.firma.yonetimi.0c7cc244", table: .paywall, fallback: "Firma yönetimi")
        ]
    }

    static var freeVersusPlusRows: [PaywallDesignComparisonRow] {
        [
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.gunluk.analiz.924d4a67", table: .paywall, fallback: "Günlük analiz"),
                left: .text(
                    RDLocalization.string("paywall.in.app.paywall.view.1.gun.48502c81", table: .paywall, fallback: "1 / gün"),
                    PaywallDesignColor.muted
                ),
                right: .text(
                    RDLocalization.string("paywall.in.app.paywall.view.10.gun.f71707af", table: .paywall, fallback: "10 / gün"),
                    PaywallDesignColor.orange
                )
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.risk.analizi.61b95913", table: .paywall, fallback: "Risk Analizi"),
                left: .cross,
                right: .check(PaywallDesignColor.orange)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.detayli.analiz.e955c96b", table: .paywall, fallback: "Detaylı analiz"),
                left: .cross,
                right: .check(PaywallDesignColor.orange)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.derin.arastirma.20ba0421", table: .paywall, fallback: "Derin Araştırma"),
                left: .cross,
                right: .check(PaywallDesignColor.orange)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.coklu.fotograf.analizi.c5d7318b", table: .paywall, fallback: "Çoklu Fotoğraf Analizi"),
                left: .cross,
                right: .check(PaywallDesignColor.orange)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.firma.yonetimi.0c7cc244", table: .paywall, fallback: "Firma yönetimi"),
                left: .cross,
                right: .check(PaywallDesignColor.orange)
            )
        ]
    }

    static var plusVersusProRows: [PaywallDesignComparisonRow] {
        let unlimited = RDLocalization.string("paywall.design.value.unlimited", table: .paywall, fallback: "Limitsiz")
        return [
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.gunluk.analiz.924d4a67", table: .paywall, fallback: "Günlük analiz"),
                left: .text(
                    RDLocalization.string("paywall.in.app.paywall.view.10.gun.f71707af", table: .paywall, fallback: "10 / gün"),
                    PaywallDesignColor.orange
                ),
                right: .text(unlimited, PaywallDesignColor.green)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.risk.analizi.61b95913", table: .paywall, fallback: "Risk Analizi"),
                left: .check(PaywallDesignColor.orange),
                right: .check(PaywallDesignColor.green)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.detayli.analiz.e955c96b", table: .paywall, fallback: "Detaylı analiz"),
                left: .check(PaywallDesignColor.orange),
                right: .check(PaywallDesignColor.green)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.derin.arastirma.20ba0421", table: .paywall, fallback: "Derin Araştırma"),
                left: .check(PaywallDesignColor.orange),
                right: .check(PaywallDesignColor.green)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.coklu.fotograf.analizi.c5d7318b", table: .paywall, fallback: "Çoklu Fotoğraf Analizi"),
                left: .check(PaywallDesignColor.orange),
                right: .check(PaywallDesignColor.green)
            ),
            PaywallDesignComparisonRow(
                title: RDLocalization.string("paywall.in.app.paywall.view.oncelikli.destek.d8c6c44d", table: .paywall, fallback: "Öncelikli destek"),
                left: .cross,
                right: .check(PaywallDesignColor.green)
            )
        ]
    }
}

extension SubscriptionPlanPackage {
    /// RevenueCat paket kimliklerinden faturalama dönemini çözer.
    func matchesDesignPaywall(_ billing: InAppPaywallBilling) -> Bool {
        let token = [id, productIdentifier, title, subtitle]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)
            .lowercased(with: .autoupdatingCurrent)

        switch billing {
        case .yearly:
            return token.contains("annual") ||
                token.contains("year") ||
                token.contains("yearly") ||
                token.contains("yillik") ||
                token.contains("yil")
        case .monthly:
            return token.contains("monthly") ||
                token.contains("month") ||
                token.contains("aylik") ||
                token.contains("ay")
        }
    }
}

#Preview("Design paywall") {
    PaywallDesignFlowView(onClose: {}, onSubscribe: {}, notice: nil)
        .environmentObject(AppState())
}
