import SwiftUI

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

struct InAppPaywallView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil

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

    private let variantID = "claude_plus_pro_paywall_v1"

    private var activeScreen: InAppPaywallScreen {
        #if DEBUG
        if Self.isUITestForceProPaywall {
            return .pro
        }
        #endif
        return screenOverride ?? (app.currentTier == .free ? .plus : .pro)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                InAppPaywallColor.paper.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        PaywallHero()
                            .frame(height: 88 + safeTop)
                            .padding(.top, -safeTop)

                        screenBody
                    }
                    .frame(maxWidth: 430, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.bottom, 132 + safeBottom)
                }
                .ignoresSafeArea(edges: .top)

                ctaTray(bottomInset: safeBottom)
                    .offset(y: 12)

                topBar(topInset: safeTop)

                if let processingOverlayTitle {
                    PaywallProcessingOverlay(
                        title: processingOverlayTitle,
                        message: processingOverlayMessage
                    )
                    .transition(.opacity)
                    .zIndex(40)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.light)
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
        .accessibilityIdentifier("in_app_paywall.\(activeScreen.rawValue)")
    }

    @ViewBuilder
    private var screenBody: some View {
        switch activeScreen {
        case .plus:
            plusBody
        case .pro:
            proBody
        }
    }

    private var plusBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductBadge(screen: .plus)
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(plusBilling == .yearly ? RDLocalization.string("paywall.in.app.paywall.view.ilk.haftaniz.bizden.5545e4d4", table: .paywall, fallback: "İlk haftanız bizden.") : RDLocalization.string("paywall.in.app.paywall.view.plus.a.abone.olun.6c6e9c29", table: .paywall, fallback: "Plus’a abone olun."))
                    .font(.system(size: RDFontScale.size(23.5), weight: .black, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.onyx)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .accessibilityIdentifier("in_app_paywall.plus.title")

                plusSubtitle
                    .font(.system(size: RDFontScale.size(11.8), weight: .regular, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.graphite)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 8)

            billingToggle(for: .plus)

            if let notice {
                NoticeCard(text: notice, isError: false)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            if plusBilling == .yearly {
                PlusTimeline(annualPrice: annualPriceText(for: .plus))
                    .padding(.top, 0)
            } else {
                Color.clear.frame(height: 48)
            }

            PlusComparison(onPro: {
                switchTo(.pro)
            })
            .padding(.top, 6)
        }
    }

    private var proBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductBadge(screen: .pro)
                .padding(.horizontal, 20)
                .padding(.top, 30)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(RDLocalization.string("paywall.in.app.paywall.view.limitsiz.ozellikler.694562c5", table: .paywall, fallback: "Limitsiz Özellikler"))
                    .font(.system(size: RDFontScale.size(28), weight: .black, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.onyx)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .accessibilityIdentifier("in_app_paywall.pro.title")

                proSubtitle
                    .font(.system(size: RDFontScale.size(13), weight: .regular, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.graphite)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 10)

            billingToggle(for: .pro)

            if let notice {
                NoticeCard(text: notice, isError: false)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            Color.clear.frame(height: 8)

            ProFeatureCard()

            Button {
                switchTo(.plus)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.goldTickForeground)
                        .frame(width: 34, height: 34)
                        .background(InAppPaywallColor.goldEdge)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(RDLocalization.string("paywall.in.app.paywall.view.plus.aboneligini.incele.847e9604", table: .paywall, fallback: "Plus aboneliğini incele"))
                            .font(.system(size: RDFontScale.size(13.5), weight: .bold, design: .rounded))
                            .foregroundStyle(InAppPaywallColor.onyx)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(RDLocalization.string("paywall.in.app.paywall.view.daha.uygun.fiyatli.baslangic.paketi.751d7f54", table: .paywall, fallback: "Daha uygun fiyatlı başlangıç paketi"))
                            .font(.system(size: RDFontScale.size(11.5), weight: .medium, design: .rounded))
                            .foregroundStyle(InAppPaywallColor.goldDeep)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.goldDeep)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
                .background(InAppPaywallColor.goldSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "#F4E3A8"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: InAppPaywallColor.onyx.opacity(0.04), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("in_app_paywall.pro.plus_link")
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private var plusSubtitle: Text {
        if plusBilling == .yearly {
            return Text(
                RDLocalization.format(
                    "paywall.plus.yearly.subtitle",
                    table: .paywall,
                    fallback: "Yıllık Plus %1$@. Varsa uygun teklif App Store'da uygulanır.",
                    arguments: [annualPriceText(for: .plus)]
                )
            )
        }
        return Text(
            RDLocalization.format(
                "paywall.plus.monthly.subtitle",
                table: .paywall,
                fallback: "Tüm Plus özellikleri aylık %1$@.",
                arguments: [monthlyPriceText(for: .plus)]
            )
        )
    }

    private var proSubtitle: Text {
        if proBilling == .yearly {
            return Text(
                RDLocalization.format(
                    "paywall.pro.yearly.subtitle",
                    table: .paywall,
                    fallback: "Yıllık %1$@ ile tüm Pro özellikleri.",
                    arguments: [annualPriceText(for: .pro)]
                )
            )
        }
        return Text(
            RDLocalization.format(
                "paywall.pro.monthly.subtitle",
                table: .paywall,
                fallback: "Tüm Pro özellikleri aylık %1$@ ile.",
                arguments: [monthlyPriceText(for: .pro)]
            )
        )
    }

    private func topBar(topInset: CGFloat) -> some View {
        VStack {
            HStack {
                Button(action: closePaywall) {
                    Image(systemName: "xmark")
                        .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.onyx)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.94))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .opacity(isWorking ? 0.55 : 1)
                .accessibilityLabel(RDLocalization.string("paywall.in.app.paywall.view.paywall.ekranini.kapat.92144bcc", table: .paywall, fallback: "Paywall ekranını kapat"))

                Spacer()

                Button(action: restore) {
                    Text(isWorking ? RDLocalization.string("paywall.in.app.paywall.view.bekle.c1475169", table: .paywall, fallback: "Bekle") : RDLocalization.string("paywall.in.app.paywall.view.geri.yukle.848d560c", table: .paywall, fallback: "Geri yükle"))
                        .font(.system(size: RDFontScale.size(12.5), weight: .bold, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.onyx)
                        .padding(.horizontal, 4)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .opacity(isWorking ? 0.55 : 1)
                .accessibilityLabel(RDLocalization.string("paywall.in.app.paywall.view.satin.alimlari.geri.yukle.aece5480", table: .paywall, fallback: "Satın alımları geri yükle"))
            }
            .frame(maxWidth: 430)
            .padding(.horizontal, 20)
            .padding(.top, topInset + 12)

            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }

    private func billingToggle(for screen: InAppPaywallScreen) -> some View {
        InAppBillingToggle(
            value: billingBinding(for: screen),
            screen: screen
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
    }

    private func ctaTray(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let visibleError {
                NoticeCard(text: visibleError, isError: true)
                    .padding(.bottom, 10)
            }

            if let workingMessage {
                NoticeCard(text: workingMessage, isError: false)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if activeScreen == .plus && billing(for: .plus) == .yearly {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: RDFontScale.size(11), weight: .black, design: .rounded))
                    Text(RDLocalization.string("paywall.in.app.paywall.view.su.an.odeme.yok.52dc209d", table: .paywall, fallback: "Fiyat ve uygun teklifler App Store'da doğrulanır"))
                        .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                }
                .foregroundStyle(InAppPaywallColor.onyx)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            }

            Button(action: handlePrimaryAction) {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .tint(Color.white)
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .accessibilityIdentifier(selectedPackage == nil ? "in_app_paywall.cta.loading" : "in_app_paywall.cta.ready")
                }
                .foregroundStyle(primaryButtonDisabled ? InAppPaywallColor.graphite.opacity(0.62) : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(primaryButtonDisabled ? InAppPaywallColor.fog : InAppPaywallColor.green)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(
                    color: primaryButtonDisabled ? .clear : InAppPaywallColor.green.opacity(0.30),
                    radius: 12,
                    x: 0,
                    y: 5
                )
            }
            .buttonStyle(.plain)
            .disabled(primaryButtonDisabled)
            .accessibilityIdentifier("in_app_paywall.cta")

            Text(legalLine)
                .font(.system(size: RDFontScale.size(11.5), weight: .regular, design: .rounded))
                .foregroundStyle(InAppPaywallColor.slate)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 7)

            Text(RDLocalization.string("paywall.in.app.paywall.view.istediginiz.zaman.iptal.edebilirsiniz.otomatik.y.287937e3", table: .paywall, fallback: "İstediğiniz zaman iptal edebilirsiniz · Otomatik yenilenir"))
                .font(.system(size: RDFontScale.size(10), weight: .regular, design: .rounded))
                .foregroundStyle(InAppPaywallColor.slate)
                .multilineTextAlignment(.center)
                .padding(.top, activeScreen == .plus && billing(for: .plus) == .yearly ? 2 : 6)

            HStack(spacing: 16) {
                legalLink(RDLocalization.string("paywall.in.app.paywall.view.sartlar.f0fe46a2", table: .paywall, fallback: "Şartlar"), document: .terms)
                legalLink("Gizlilik", document: .privacy)
                legalLink(RDLocalization.string("paywall.in.app.paywall.view.iptal.hakki.fd1920ba", table: .paywall, fallback: "İptal hakkı"), URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, max(bottomInset * 0.18, 6))
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
        .background(InAppPaywallColor.paper)
    }

    private func legalLink(_ title: String, document: LegalDocumentKind) -> some View {
        Button {
            selectedLegalDocument = document
        } label: {
            Text(title)
                .font(.system(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
                .foregroundStyle(InAppPaywallColor.graphite)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .opacity(isWorking ? 0.55 : 1)
    }

    private func legalLink(_ title: String, _ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text(title)
                .font(.system(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
                .foregroundStyle(InAppPaywallColor.graphite)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .opacity(isWorking ? 0.55 : 1)
    }

    private var primaryButtonTitle: String {
        if isWorking { return RDLocalization.string("paywall.in.app.paywall.view.satin.alma.hazirlaniyor.7db69bb8", table: .paywall, fallback: "Satın alma hazırlanıyor...") }
        if currentPlanIncludesActiveScreen { return RDLocalization.string("paywall.in.app.paywall.view.planin.aktif.a449054e", table: .paywall, fallback: "Planın aktif") }
        if selectedPackage == nil {
            return packageLoadError == nil ? RDLocalization.string("paywall.in.app.paywall.view.fiyat.yukleniyor.9767cab5", table: .paywall, fallback: "Fiyat yükleniyor...") : RDLocalization.string("paywall.in.app.paywall.view.tekrar.dene.a5447e51", table: .paywall, fallback: "Tekrar dene")
        }
        if activeScreen == .plus && billing(for: .plus) == .yearly { return RDLocalization.string("paywall.in.app.paywall.view.ucretsiz.denemeyi.baslat.8b61966d", table: .paywall, fallback: "Devam et") }
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

    private var legalLine: String {
        switch (activeScreen, billing(for: activeScreen)) {
        case (.plus, .yearly):
            return RDLocalization.format("paywall.in.app.paywall.view.7.gun.ucretsiz.sonra.yillik.1.7e510489", table: .paywall, fallback: "Yıllık %1$@. Varsa uygun teklif App Store'da uygulanır.", arguments: [String(describing: annualPriceText(for: .plus))])
        case (.plus, .monthly):
            return RDLocalization.format("paywall.in.app.paywall.view.aylik.1.2ef43160", table: .paywall, fallback: "Aylık %1$@.", arguments: [String(describing: monthlyPriceText(for: .plus))])
        case (.pro, .yearly):
            return RDLocalization.format("paywall.in.app.paywall.view.yillik.1.f014f98c", table: .paywall, fallback: "Yıllık %1$@.", arguments: [String(describing: annualPriceText(for: .pro))])
        case (.pro, .monthly):
            return RDLocalization.format("paywall.in.app.paywall.view.aylik.1.aa596d91", table: .paywall, fallback: "Aylık %1$@.", arguments: [String(describing: monthlyPriceText(for: .pro))])
        }
    }

    private var visibleError: String? {
        errorMessage ?? packageLoadError
    }

    private var selectedPackage: SubscriptionPlanPackage? {
        selectedPackage(for: activeScreen, billing: billing(for: activeScreen))
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

    private func switchTo(_ target: InAppPaywallScreen) {
        guard !isWorking else { return }
        guard activeScreen != target else { return }
        switch target {
        case .plus:
            plusBilling = .yearly
        case .pro:
            proBilling = .yearly
        }
        screenOverride = target
        errorMessage = nil
        UISelectionFeedbackGenerator().selectionChanged()
        logPaywallEvent(.planSelect, screen: target, billing: billing(for: target))
    }

    private func billingBinding(for screen: InAppPaywallScreen) -> Binding<InAppPaywallBilling> {
        Binding(
            get: { billing(for: screen) },
            set: { newValue in
                let oldValue = billing(for: screen)
                guard oldValue != newValue else { return }
                switch screen {
                case .plus:
                    plusBilling = newValue
                case .pro:
                    proBilling = newValue
                }
                UISelectionFeedbackGenerator().selectionChanged()
                logPaywallEvent(.billingSelect, screen: screen, billing: newValue)
            }
        )
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
            source: .inApp,
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
        // Migration uygulanana kadar pending ödemeler purchase_failed olarak loglanır.
        // migrations-pending/20260630200000_paywall_payment_pending_event.sql → supabase/migrations/
        let paymentPendingPaywallEventEnabled = false

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
                    paymentPendingPaywallEventEnabled && classification.kind == .paymentPending
                        ? .paymentPending
                        : .purchaseFailed,
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
            .first { $0.matchesInAppPaywall(billing) && $0.displayPrice != nil }
    }

    private func annualPriceText(for tier: SubscriptionTier) -> String {
        priceText(for: tier, billing: .yearly)
    }

    private func monthlyPriceText(for tier: SubscriptionTier) -> String {
        priceText(for: tier, billing: .monthly)
    }

    private func priceText(for tier: SubscriptionTier, billing: InAppPaywallBilling) -> String {
        selectedPackage(for: tier == .plus ? .plus : .pro, billing: billing)?.displayPrice
            ?? unavailablePriceText
    }

    private var unavailablePriceText: String {
        packageLoadError == nil ? RDLocalization.string("paywall.in.app.paywall.view.fiyat.yukleniyor.91a8a0da", table: .paywall, fallback: "fiyat yükleniyor") : RDLocalization.string("paywall.in.app.paywall.view.fiyat.alinamadi.50d6ae8c", table: .paywall, fallback: "fiyat alınamadı")
    }

    #if DEBUG
    private static var isUITestForceProPaywall: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_FORCE_PRO_PAYWALL")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_FORCE_PRO_PAYWALL"] == "1"
    }
    #endif
}

private struct InAppPaywallColor {
    static let onyx = Color(hex: "#0B0D0E")
    static let graphite = Color(hex: "#1A1D1F")
    static let slate = Color(hex: "#6B7280")
    static let line = Color(hex: "#DDE3E0")
    static let paper = Color(hex: "#FAFBFA")
    static let white = Color.white
    static let fog = Color(hex: "#F1F4F2")
    static let cloud = Color(hex: "#F6F7F6")
    static let green = Color(hex: "#00B82E")
    static let greenDark = Color(hex: "#008F24")
    static let greenSoft = Color(hex: "#EAF8EE")
    static let goldBase = Color(hex: "#D4A106")
    static let goldDeep = Color(hex: "#A37C04")
    static let goldSoft = Color(hex: "#FEF6CE")
    static let goldEdge = Color(hex: "#F4D04A")
    static let goldTickForeground = Color(hex: "#7A5C00")
}

private struct PaywallHero: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Color(hex: "#0C7A21"), Color(hex: "#0F8F2A"), Color(hex: "#11A632")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                center: UnitPoint(x: 0.80, y: 0.20),
                startRadius: 0,
                endRadius: 170
            )

            RadialGradient(
                colors: [InAppPaywallColor.greenDark.opacity(0.95), InAppPaywallColor.green.opacity(0)],
                center: UnitPoint(x: 0.10, y: 1.0),
                startRadius: 0,
                endRadius: 220
            )

            HeroGrid()
                .opacity(0.08)

            HardHatWatermark()
                .frame(width: 220, height: 220)
                .opacity(0.20)
                .offset(x: 28, y: 56)
        }
        .clipped()
    }
}

private struct HeroGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 22

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(Color.white), lineWidth: 0.6)
        }
    }
}

private struct HardHatWatermark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 64
            let transform = CGAffineTransform(scaleX: scale, y: scale)

            func scaled(_ path: Path) -> Path {
                path.applying(transform)
            }

            var hat = Path()
            hat.move(to: CGPoint(x: 5, y: 45))
            hat.addQuadCurve(to: CGPoint(x: 59, y: 45), control: CGPoint(x: 32, y: 52))
            hat.move(to: CGPoint(x: 9, y: 45))
            hat.addQuadCurve(to: CGPoint(x: 55, y: 45), control: CGPoint(x: 32, y: 49))
            hat.move(to: CGPoint(x: 11, y: 45))
            hat.addQuadCurve(to: CGPoint(x: 32, y: 16), control: CGPoint(x: 11, y: 18))
            hat.addQuadCurve(to: CGPoint(x: 53, y: 45), control: CGPoint(x: 53, y: 18))
            hat.move(to: CGPoint(x: 32, y: 16))
            hat.addQuadCurve(to: CGPoint(x: 32, y: 44), control: CGPoint(x: 31.5, y: 30))
            hat.move(to: CGPoint(x: 22, y: 17.5))
            hat.addQuadCurve(to: CGPoint(x: 22, y: 44), control: CGPoint(x: 20.5, y: 30))
            hat.move(to: CGPoint(x: 42, y: 17.5))
            hat.addQuadCurve(to: CGPoint(x: 42, y: 44), control: CGPoint(x: 43.5, y: 30))
            hat.addEllipse(in: CGRect(x: 29.4, y: 23.4, width: 5.2, height: 5.2))
            hat.move(to: CGPoint(x: 14, y: 41))
            hat.addQuadCurve(to: CGPoint(x: 22, y: 52), control: CGPoint(x: 14, y: 50))
            hat.move(to: CGPoint(x: 50, y: 41))
            hat.addQuadCurve(to: CGPoint(x: 42, y: 52), control: CGPoint(x: 50, y: 50))

            context.stroke(
                scaled(hat),
                with: .color(Color.white),
                style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private struct ProductBadge: View {
    let screen: InAppPaywallScreen

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: screen == .plus ? "crown.fill" : "star.fill")
                .font(.system(size: screen == .plus ? 12 : 11, weight: .black, design: .rounded))
                .foregroundStyle(iconColor)

            Text(screen == .plus ? "PLUS" : "PRO")
                .font(.system(size: RDFontScale.size(12), weight: .black, design: .rounded))
                .foregroundStyle(textColor)
                .tracking(0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 22)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(borderColor, lineWidth: screen == .plus ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityIdentifier("in_app_paywall.\(screen.rawValue).badge")
    }

    private var background: Color {
        screen == .plus ? InAppPaywallColor.goldSoft : InAppPaywallColor.onyx
    }

    private var textColor: Color {
        screen == .plus ? InAppPaywallColor.goldDeep : Color.white
    }

    private var iconColor: Color {
        screen == .plus ? InAppPaywallColor.goldBase : InAppPaywallColor.green
    }

    private var borderColor: Color {
        screen == .plus ? Color(hex: "#F4E3A8") : Color.clear
    }
}

private struct InAppBillingToggle: View {
    @Binding var value: InAppPaywallBilling
    let screen: InAppPaywallScreen

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                option(.monthly)
                option(.yearly)
            }
            .padding(3)
            .background(InAppPaywallColor.fog)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("in_app_paywall.billing_toggle")
    }

    private func option(_ option: InAppPaywallBilling) -> some View {
        Button {
            value = option
        } label: {
            HStack(spacing: 6) {
                Text(option.title)
                    .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                    .foregroundStyle(value == option ? InAppPaywallColor.onyx : InAppPaywallColor.slate)

                if option == .yearly {
                    Text(RDLocalization.string("paywall.in.app.paywall.view.17.468b19d3", table: .paywall, fallback: "%17"))
                        .font(.system(size: RDFontScale.size(9), weight: .black, design: .rounded))
                        .foregroundStyle(tagForeground(selected: value == option))
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(tagBackground(selected: value == option))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(tagBorder(selected: value == option), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .frame(width: option == .yearly ? 104 : 86, height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(value == option ? Color.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(
                color: value == option ? InAppPaywallColor.onyx.opacity(0.08) : .clear,
                radius: 3,
                x: 0,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityIdentifier("in_app_paywall.billing.\(option.rawValue)")
    }

    private func tagForeground(selected: Bool) -> Color {
        guard selected else { return InAppPaywallColor.slate }
        return screen == .plus ? InAppPaywallColor.goldDeep : InAppPaywallColor.greenDark
    }

    private func tagBackground(selected: Bool) -> Color {
        guard selected else { return InAppPaywallColor.cloud }
        return screen == .plus ? InAppPaywallColor.goldSoft : InAppPaywallColor.greenSoft
    }

    private func tagBorder(selected: Bool) -> Color {
        guard selected else { return Color.clear }
        return screen == .plus ? Color(hex: "#F4E3A8") : InAppPaywallColor.greenDark.opacity(0.25)
    }
}

private struct PlusTimeline: View {
    let annualPrice: String

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [InAppPaywallColor.green, InAppPaywallColor.green, InAppPaywallColor.goldEdge],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 2)
            .clipShape(Capsule())
            .padding(.leading, 15)
            .padding(.vertical, 13)

            VStack(alignment: .leading, spacing: 7) {
                TimelineRow(icon: "lock.open.fill", label: RDLocalization.string("paywall.in.app.paywall.view.bugun.936ba16e", table: .paywall, fallback: "Bugün"), detail: RDLocalization.string("paywall.in.app.paywall.view.tum.plus.ozelliklerinin.kilidini.acin.ba20643f", table: .paywall, fallback: "Tüm Plus özelliklerinin kilidini açın."), tone: .green)
                TimelineRow(icon: "checkmark.seal.fill", label: RDLocalization.string("paywall.in.app.paywall.view.5.gun.d7dc9e6f", table: .paywall, fallback: "App Store"), detail: RDLocalization.string("paywall.in.app.paywall.view.denemenizin.bittigine.dair.hatirlatma.alin.6eea147c", table: .paywall, fallback: "Fiyatı ve varsa uygun teklifi App Store onay ekranında doğrulayın."), tone: .green)
                TimelineRow(icon: "crown.fill", label: RDLocalization.string("paywall.in.app.paywall.view.7.gun.ec8fc3fe", table: .paywall, fallback: "Yıllık plan"), detail: RDLocalization.format("paywall.in.app.paywall.view.yillik.1.odeme.alinir.10a000c7", table: .paywall, fallback: "Yıllık fiyat %1$@; App Store şartları geçerlidir.", arguments: [String(describing: annualPrice)]), tone: .gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(InAppPaywallColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: InAppPaywallColor.onyx.opacity(0.07), radius: 18, x: 6, y: 8)
        .shadow(color: InAppPaywallColor.onyx.opacity(0.04), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("in_app_paywall.plus.timeline")
    }
}

private enum TimelineTone {
    case green
    case gold
}

private struct TimelineRow: View {
    let icon: String
    let label: String
    let detail: String
    let tone: TimelineTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(12), weight: .black, design: .rounded))
                .foregroundStyle(iconForeground)
                .frame(width: 27, height: 27)
                .background(iconBackground)
                .clipShape(Circle())
                .shadow(color: shadowColor, radius: 8, x: 0, y: 3)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.onyx)
                Text(detail)
                    .font(.system(size: RDFontScale.size(11.2), weight: .regular, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.slate)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var iconBackground: Color {
        tone == .green ? InAppPaywallColor.green : InAppPaywallColor.goldEdge
    }

    private var iconForeground: Color {
        tone == .green ? Color.white : InAppPaywallColor.goldTickForeground
    }

    private var shadowColor: Color {
        tone == .green ? InAppPaywallColor.greenDark.opacity(0.22) : InAppPaywallColor.goldBase.opacity(0.28)
    }
}

private struct PlusComparisonFeature: Identifiable {
    let label: String
    let free: ComparisonValue
    let plus: ComparisonValue
    let badge: String?

    var id: String { label }
}

private enum ComparisonValue: Equatable {
    case text(String)
    case included
    case notIncluded
}

private struct PlusComparison: View {
    var onPro: () -> Void

    private let features = [
        PlusComparisonFeature(label: RDLocalization.string("paywall.in.app.paywall.view.gunluk.analiz.924d4a67", table: .paywall, fallback: "Günlük analiz"), free: .text(RDLocalization.string("paywall.in.app.paywall.view.1.gun.48502c81", table: .paywall, fallback: "1 / gün")), plus: .text(RDLocalization.string("paywall.in.app.paywall.view.10.gun.f71707af", table: .paywall, fallback: "10 / gün")), badge: nil),
        PlusComparisonFeature(label: RDLocalization.string("paywall.in.app.paywall.view.risk.analizi.61b95913", table: .paywall, fallback: "Risk Analizi"), free: .notIncluded, plus: .included, badge: nil),
        PlusComparisonFeature(label: RDLocalization.string("paywall.in.app.paywall.view.detayli.analiz.e955c96b", table: .paywall, fallback: "Detaylı analiz"), free: .notIncluded, plus: .included, badge: nil),
        PlusComparisonFeature(label: RDLocalization.string("paywall.in.app.paywall.view.derin.arastirma.20ba0421", table: .paywall, fallback: "Derin Araştırma"), free: .notIncluded, plus: .included, badge: nil),
        PlusComparisonFeature(label: RDLocalization.string("paywall.in.app.paywall.view.firma.yonetimi.0c7cc244", table: .paywall, fallback: "Firma yönetimi"), free: .notIncluded, plus: .included, badge: nil),
        PlusComparisonFeature(label: RDLocalization.string("paywall.in.app.paywall.view.coklu.fotograf.analizi.c5d7318b", table: .paywall, fallback: "Çoklu Fotoğraf Analizi"), free: .notIncluded, plus: .included, badge: RDLocalization.string("paywall.in.app.paywall.view.yeni.0a06228d", table: .paywall, fallback: "YENİ"))
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(RDLocalization.string("paywall.in.app.paywall.view.neler.dahil.36a09b8b", table: .paywall, fallback: "Neler dahil?"))
                    .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.onyx)
                    .accessibilityIdentifier("in_app_paywall.plus.included_title")
                Image(systemName: "chevron.down")
                    .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.slate)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 0)

            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(InAppPaywallColor.goldSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "#F4E3A8"), lineWidth: 1)
                    )
                    .frame(width: 64)
                    .padding(.trailing, 20)

                VStack(spacing: 0) {
                    comparisonHeader
                    ForEach(features) { feature in
                        comparisonRow(feature)
                    }
                }
                .padding(.horizontal, 20)
            }

            Button(action: onPro) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.green)

                    Text(RDLocalization.string("paywall.in.app.paywall.view.limitsiz.ozellikler.icin.6733cee8", table: .paywall, fallback: "Limitsiz özellikler için"))
                        .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                        .foregroundColor(InAppPaywallColor.onyx)
                    + Text(RDLocalization.string("paywall.in.app.paywall.view.pro.yu.incele.8f867e6b", table: .paywall, fallback: "PRO’yu incele"))
                        .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                        .underline()
                        .foregroundColor(InAppPaywallColor.onyx)

                    Image(systemName: "chevron.right")
                        .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.slate)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("in_app_paywall.plus.pro_link")
            .padding(.top, 2)
        }
    }

    private var comparisonHeader: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Text(RDLocalization.string("paywall.in.app.paywall.view.ucretsiz.61d66735", table: .paywall, fallback: "FREE"))
                .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                .foregroundStyle(InAppPaywallColor.slate)
                .frame(width: 56)

            VStack(spacing: 2) {
                Text(RDLocalization.string("paywall.in.app.paywall.view.populer.1df05921", table: .paywall, fallback: "POPÜLER"))
                    .font(.system(size: RDFontScale.size(8.5), weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(height: 14)
                    .background(InAppPaywallColor.green)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: InAppPaywallColor.greenDark.opacity(0.25), radius: 4, x: 0, y: 2)

                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.goldBase)
                    Text(RDLocalization.string("paywall.in.app.paywall.view.plus.6c6df3b6", table: .paywall, fallback: "PLUS"))
                        .font(.system(size: RDFontScale.size(12), weight: .black, design: .rounded))
                        .foregroundStyle(InAppPaywallColor.goldDeep)
                }
            }
            .frame(width: 64)
        }
        .frame(height: 34)
    }

    private func comparisonRow(_ feature: PlusComparisonFeature) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(feature.label)
                    .font(.system(size: RDFontScale.size(11.5), weight: .medium, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.graphite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let badge = feature.badge {
                    Text(badge)
                        .font(.system(size: RDFontScale.size(8), weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .frame(height: 12)
                        .background(InAppPaywallColor.onyx)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ComparisonCell(value: feature.free, isPlus: false)
                .frame(width: 56)

            ComparisonCell(value: feature.plus, isPlus: true)
                .frame(width: 64)
        }
        .frame(height: 27)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(InAppPaywallColor.line)
                .frame(height: 1)
        }
    }
}

private struct ComparisonCell: View {
    let value: ComparisonValue
    let isPlus: Bool

    var body: some View {
        switch value {
        case .included:
            Image(systemName: "checkmark")
                .font(.system(size: RDFontScale.size(11), weight: .black, design: .rounded))
                .foregroundStyle(InAppPaywallColor.goldTickForeground)
                .frame(width: 20, height: 20)
                .background(InAppPaywallColor.goldEdge)
                .clipShape(Circle())
        case .notIncluded:
            Image(systemName: "xmark")
                .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "#C2C8C5"))
                .frame(width: 20, height: 20)
        case let .text(text):
            Text(text)
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .monospaced))
                .foregroundStyle(isPlus ? InAppPaywallColor.goldDeep : InAppPaywallColor.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct ProFeatureCard: View {
    private let items: [(label: String, strong: Bool)] = [
        (RDLocalization.string("paywall.in.app.paywall.view.tum.plus.ozellikleri.dahil.7a0cdd58", table: .paywall, fallback: "Tüm Plus özellikleri dahil"), true),
        (RDLocalization.string("paywall.in.app.paywall.view.limitsiz.gunluk.analiz.117c9b5e", table: .paywall, fallback: "Limitsiz günlük analiz"), false),
        (RDLocalization.string("paywall.in.app.paywall.view.limitsiz.risk.analizi.0208fc64", table: .paywall, fallback: "Limitsiz risk analizi"), false),
        (RDLocalization.string("paywall.in.app.paywall.view.limitsiz.detayli.analiz.2806a268", table: .paywall, fallback: "Limitsiz detaylı analiz"), false),
        (RDLocalization.string("paywall.in.app.paywall.view.limitsiz.derin.arastirma.74201aad", table: .paywall, fallback: "Limitsiz derin araştırma"), false),
        (RDLocalization.string("paywall.in.app.paywall.view.oncelikli.destek.d8c6c44d", table: .paywall, fallback: "Öncelikli destek"), false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: RDFontScale.size(13), weight: .black, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.green)
                    .frame(width: 28, height: 28)
                    .background(InAppPaywallColor.onyx)
                    .clipShape(Circle())

                Text(RDLocalization.string("paywall.in.app.paywall.view.pro.uyelik.74a41cf4", table: .paywall, fallback: "Pro üyelik"))
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .foregroundStyle(InAppPaywallColor.onyx)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.label) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: RDFontScale.size(10), weight: .black, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(width: 18, height: 18)
                            .background(InAppPaywallColor.green)
                            .clipShape(Circle())

                        Text(item.label)
                            .font(.system(size: RDFontScale.size(13.5), weight: item.strong ? .bold : .medium, design: .rounded))
                            .foregroundStyle(item.strong ? InAppPaywallColor.onyx : InAppPaywallColor.graphite)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                Color.white
                RadialGradient(
                    colors: [InAppPaywallColor.greenSoft, InAppPaywallColor.greenSoft.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 70
                )
                .frame(width: 120, height: 120)
                .offset(x: 40, y: -40)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(InAppPaywallColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: InAppPaywallColor.onyx.opacity(0.07), radius: 18, x: 6, y: 8)
        .shadow(color: InAppPaywallColor.onyx.opacity(0.04), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("in_app_paywall.pro.features")
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

private struct NoticeCard: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
                .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                .foregroundStyle(isError ? Color.rdCritical : InAppPaywallColor.greenDark)

            Text(text)
                .font(.system(size: RDFontScale.size(12.5), weight: .medium, design: .rounded))
                .foregroundStyle(InAppPaywallColor.graphite)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(isError ? Color.rdCritical.opacity(0.08) : InAppPaywallColor.greenSoft)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isError ? Color.rdCritical.opacity(0.12) : InAppPaywallColor.greenDark.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension SubscriptionPlanPackage {
    func matchesInAppPaywall(_ billing: InAppPaywallBilling) -> Bool {
        let token = [
            id,
            productIdentifier,
            title,
            subtitle
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)
        .lowercased(with: .autoupdatingCurrent)

        switch billing {
        case .yearly:
            return token.contains("annual") ||
                token.contains("year") ||
                token.contains("yearly") ||
                token.contains("yillik") ||
                token.contains("yıllık") ||
                token.contains("yılık") ||
                token.contains("yil")
        case .monthly:
            return token.contains("monthly") ||
                token.contains("month") ||
                token.contains("aylik") ||
                token.contains("aylık") ||
                token.contains("ay")
        }
    }
}

#Preview("In-app Plus Paywall") {
    InAppPaywallView(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
