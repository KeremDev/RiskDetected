import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil

    @State private var selectedTier: SubscriptionTier = .plus
    @State private var billing: PaywallBilling = .yearly
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let paper = Color(hex: "#F5F6F4")
    private let cloud = Color(hex: "#EEF0EC")
    private let onyx = Color(hex: "#0B0D0E")
    private let graphite = Color(hex: "#1A1D1F")
    private let slate = Color(hex: "#6B7280")
    private let line = Color(hex: "#E4E7E4")
    private let green = Color(hex: "#1FB94B")
    private let greenDark = Color(hex: "#159638")
    private let greenSoft = Color(hex: "#E8F6EC")
    private let amber = Color(hex: "#C56B12")
    private let amberSoft = Color(hex: "#FFF0D8")

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 40, 280)

            ZStack(alignment: .top) {
                paper.ignoresSafeArea()
                heroBackground(width: proxy.size.width)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear
                            .frame(height: 170)

                        billingToggle

                        if let notice {
                            noticeCard(notice)
                        }

                        Color.clear.frame(height: 4)
                        freePlanStrip
                        Color.clear.frame(height: 8)

                        HStack(alignment: .top, spacing: 10) {
                            paidPlanCard(.plus, recommended: true)
                            paidPlanCard(.pro, recommended: false)
                        }

                        if let errorMessage {
                            noticeCard(errorMessage)
                        }

                        if let packageLoadError {
                            noticeCard(packageLoadError)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 188)
                }
                .frame(width: proxy.size.width)

                topBar(width: contentWidth)

                VStack {
                    Spacer()
                    ctaTray(width: contentWidth, bottomInset: proxy.safeAreaInsets.bottom)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .preferredColorScheme(.light)
        .task {
            await app.refreshSubscriptionOfferings()
            alignBillingWithAvailablePackage()
            if app.currentTier == .plus {
                selectedTier = .pro
            } else if app.currentTier == .pro {
                selectedTier = .pro
            }
        }
        .onChange(of: app.subscriptionPackages) { _ in
            alignBillingWithAvailablePackage()
        }
        .onChange(of: selectedTier) { _ in
            alignBillingWithAvailablePackage()
        }
    }

    private func heroBackground(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            paper

            Image("PaywallHero")
                .resizable()
                .scaledToFill()
                .frame(width: width, height: 350)
                .clipped()

            LinearGradient(stops: [
                .init(color: paper.opacity(0.0), location: 0.0),
                .init(color: paper.opacity(0.0), location: 0.46),
                .init(color: paper.opacity(0.36), location: 0.74),
                .init(color: paper, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: 350)
        }
        .frame(width: width, height: 350, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private func topBar(width: CGFloat) -> some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(graphite)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paywall ekranını kapat")

            Spacer()

            Button {
                restore()
            } label: {
                Text(isWorking ? "Bekle" : "Geri yükle")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(graphite)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel("Satın alımları geri yükle")
        }
        .frame(width: width)
        .padding(.top, 8)
    }

    private var billingToggle: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    billingOption(.yearly)
                    billingOption(.monthly)
                }
                .padding(4)
                .background(cloud)
                .clipShape(Capsule())
                .padding(.top, 10)

                giftBadge
                    .position(x: proxy.size.width * 0.28, y: 10)
            }
        }
        .frame(height: 52)
    }

    private func billingOption(_ option: PaywallBilling) -> some View {
        Button {
            billing = option
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            ZStack {
                Capsule()
                    .fill(billing == option ? Color.white : Color.clear)
                    .shadow(color: billing == option ? Color.black.opacity(0.08) : .clear, radius: 6, x: 0, y: 2)
                Text(option.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(billing == option ? onyx : slate)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
    }

    private var giftBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "gift.fill")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Text("2 AY HEDİYE")
                .font(.system(size: 11, weight: .black, design: .rounded))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(green)
        .clipShape(Capsule())
        .shadow(color: green.opacity(0.32), radius: 10, x: 0, y: 4)
        .opacity(billing == .yearly ? 1 : 0.0)
        .animation(.easeInOut(duration: 0.18), value: billing)
    }

    private var freePlanStrip: some View {
        let selected = selectedTier == .free
        let isCurrent = app.currentTier == .free

        return Button {
            selectedTier = .free
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 10) {
                radio(checked: selected, size: 21)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Ücretsiz")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(onyx)
                        Text("· \(isCurrent ? "Mevcut planın" : "Başlangıç")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(slate)
                    }

                    Text("1 analiz/gün · Standart rapor · Kısıtlı özellikler")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(slate)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 8)

                Text("₺0")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(onyx)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? greenSoft : Color.white.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? green : line, lineWidth: selected ? 1.7 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ücretsiz plan, 1 analiz gün, ücretsiz")
    }

    private func paidPlanCard(_ tier: SubscriptionTier, recommended: Bool) -> some View {
        let selected = selectedTier == tier
        let display = planDisplay(for: tier)
        let current = app.currentTier == tier

        return Button {
            selectedTier = tier
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 7) {
                    radio(checked: selected, size: 19)

                    Text(tier.title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(onyx)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(pricePerMonthText(for: tier))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(onyx)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text("/ay")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(slate)
                    }

                    Text(periodText(for: tier))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(slate)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                if let trialDays = display.trialDays {
                    trialChip(days: trialDays)
                } else {
                    Color.clear.frame(height: 22)
                }

                Rectangle()
                    .fill(line)
                    .frame(height: 1)
                    .padding(.vertical, 0)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(display.features, id: \.self) { feature in
                        featureLine(feature)
                    }
                }

                Spacer(minLength: 0)

                if current {
                    currentPlanPill
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 256, alignment: .topLeading)
            .background(selected ? greenSoft.opacity(0.62) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected ? green : line, lineWidth: selected ? 2.1 : 1.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: selected ? green.opacity(0.1) : Color.black.opacity(0.025), radius: selected ? 14 : 6, x: 0, y: 7)
            .overlay(alignment: .top) {
                if recommended {
                    Text("EN POPÜLER")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(green)
                        .clipShape(Capsule())
                        .shadow(color: green.opacity(0.3), radius: 10, x: 0, y: 4)
                        .offset(y: -12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.title) planı, \(periodText(for: tier))")
    }

    private func radio(checked: Bool, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(checked ? green : Color(hex: "#C7CFCA"), lineWidth: 2)
                .background(Circle().fill(Color.white))

            if checked {
                Circle()
                    .fill(green)
                    .padding(5)
            }
        }
        .frame(width: size, height: size)
    }

    private func trialChip(days: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "gift.fill")
                .font(.system(size: 9, weight: .bold, design: .rounded))
            Text("\(days) GÜN ÜCRETSİZ")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .foregroundStyle(greenDark)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(greenSoft)
        .clipShape(Capsule())
    }

    private func featureLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(green)
                .frame(width: 12)

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(graphite)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
    }

    private var currentPlanPill: some View {
        Text("Plana Sahipsin")
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(amber)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(amberSoft)
            .clipShape(Capsule())
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdCritical)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(graphite)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.rdCritical.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdCritical.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func ctaTray(width: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 6) {
            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .tint(Color.white)
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                }
                .foregroundStyle(primaryButtonForeground)
                .frame(width: width)
                .frame(height: 50)
                .background(primaryButtonBackground)
                .clipShape(Capsule())
                .shadow(color: primaryButtonDisabled ? Color.clear : green.opacity(0.34), radius: 18, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(primaryButtonDisabled)

            Text(legalese)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(slate)
                .lineSpacing(1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)

            HStack(spacing: 16) {
                legalLink("Şartlar", RDConfig.Web.termsURL)
                legalLink("Gizlilik", RDConfig.Web.privacyPolicyURL)
                legalLink("İptal hakkı", URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, max(bottomInset, 8))
        .frame(width: width + 40)
        .background(
            paper
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(line)
                        .frame(height: 1)
                }
        )
    }

    private func legalLink(_ title: String, _ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(graphite)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private var primaryButtonTitle: String {
        if isWorking { return "İşleniyor..." }
        if selectedTier == .free { return "Ücretsiz ile devam et" }
        if app.currentTier == selectedTier { return "Planın aktif" }
        if selectedPackage == nil && packageLoadError != nil { return "Tekrar dene" }
        if selectedPackage == nil { return "Paket yükleniyor..." }
        if let days = planDisplay(for: selectedTier).trialDays {
            return "\(days) Gün Ücretsiz Dene"
        }
        return "\(selectedTier.title)'a Geç"
    }

    private var primaryButtonForeground: Color {
        if selectedTier.isPaid && selectedPackage == nil && packageLoadError != nil { return Color.white }
        if selectedTier.isPaid && selectedPackage == nil { return graphite }
        if selectedTier.isPaid && app.currentTier == selectedTier { return graphite }
        return selectedTier == .free ? graphite : Color.white
    }

    private var primaryButtonBackground: Color {
        if selectedTier.isPaid && selectedPackage == nil && packageLoadError != nil { return green }
        if selectedTier.isPaid && selectedPackage == nil { return cloud }
        if selectedTier.isPaid && app.currentTier == selectedTier { return cloud }
        return selectedTier == .free ? cloud : green
    }

    private var primaryButtonDisabled: Bool {
        isWorking ||
            (selectedTier.isPaid && selectedPackage == nil && packageLoadError == nil) ||
            (selectedTier.isPaid && app.currentTier == selectedTier)
    }

    private var legalese: String {
        guard selectedTier.isPaid else {
            return "Mevcut Ücretsiz planında kalırsın. İstediğin zaman yükseltebilirsin."
        }

        let plan = planDisplay(for: selectedTier)
        let period = billing == .yearly
            ? "yılda \(annualTotalText(for: selectedTier))"
            : "aylık \(monthlyTotalText(for: selectedTier))"
        let gift = billing == .yearly ? " (2 ay hediye dahil)" : ""

        if let days = plan.trialDays {
            return "\(days) gün ücretsiz, sonra \(period) olarak otomatik faturalanır\(gift). Dilediğin zaman App Store ayarlarından iptal edebilirsin."
        }
        return "\(period.capitalized(with: Locale(identifier: "tr_TR"))) olarak otomatik faturalanır\(gift). Dilediğin zaman App Store ayarlarından iptal edebilirsin."
    }

    private var selectedPackage: SubscriptionPlanPackage? {
        package(for: selectedTier, billing: billing)
    }

    private var packageLoadError: String? {
        guard selectedTier.isPaid,
              selectedPackage == nil else {
            return nil
        }
        if app.subscriptionPackages.isEmpty && app.subscriptionState.errorMessage == nil {
            return nil
        }
        return "Seçili abonelik paketi şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene."
    }

    private func packages(for tier: SubscriptionTier) -> [SubscriptionPlanPackage] {
        app.subscriptionPackages.filter { $0.tier == tier }
    }

    private func package(for tier: SubscriptionTier, billing: PaywallBilling) -> SubscriptionPlanPackage? {
        guard tier.isPaid else { return nil }
        let tierPackages = packages(for: tier)
        guard !tierPackages.isEmpty else { return nil }
        return tierPackages.first(where: { package in
            package.matches(billing)
        })
    }

    private func handlePrimaryAction() {
        if selectedTier == .free {
            onClose()
            return
        }
        if selectedPackage == nil {
            reloadPackages()
            return
        }
        purchaseSelectedPlan()
    }

    private func reloadPackages() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            await app.refreshSubscriptionOfferings()
            alignBillingWithAvailablePackage()
            isWorking = false
        }
    }

    private func purchaseSelectedPlan() {
        guard let selectedPackage else {
            errorMessage = "Bu plan için App Store paketi henüz yüklenmedi."
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await app.purchaseSubscription(packageID: selectedPackage.id)
                isWorking = false
                onSubscribe()
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await app.restoreSubscriptions()
                isWorking = false
                onSubscribe()
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func alignBillingWithAvailablePackage() {
        guard selectedTier.isPaid, selectedPackage == nil else { return }
        if package(for: selectedTier, billing: .yearly) != nil {
            billing = .yearly
        } else if package(for: selectedTier, billing: .monthly) != nil {
            billing = .monthly
        }
    }

    private func planDisplay(for tier: SubscriptionTier) -> PaywallPlanDisplay {
        switch tier {
        case .free:
            return PaywallPlanDisplay(
                yearlyMonthlyPrice: 0,
                monthlyPrice: 0,
                yearlyPrice: 0,
                trialDays: nil,
                features: []
            )
        case .plus:
            return PaywallPlanDisplay(
                yearlyMonthlyPrice: 166.58,
                monthlyPrice: 199.90,
                yearlyPrice: 1_999,
                trialDays: 7,
                features: [
                    "10/gün analiz",
                    "PDF/Excel",
                    "Fine-Kinney",
                    "5×5 Matris"
                ]
            )
        case .pro:
            return PaywallPlanDisplay(
                yearlyMonthlyPrice: 416.58,
                monthlyPrice: 499.90,
                yearlyPrice: 4_999,
                trialDays: nil,
                features: [
                    "Plus + ekstra",
                    "40/gün analiz",
                    "750 rapor/ay",
                    "Prosedür kontrolü"
                ]
            )
        }
    }

    private func pricePerMonthText(for tier: SubscriptionTier) -> String {
        let fallback = planDisplay(for: tier)
        guard let selectedPackage = package(for: tier, billing: billing) else {
            return billing == .yearly
                ? Self.currency(fallback.yearlyMonthlyPrice)
                : Self.currency(fallback.monthlyPrice)
        }

        if billing == .yearly {
            return selectedPackage.monthlyEquivalentPrice ?? selectedPackage.price
        }
        return selectedPackage.price
    }

    private func periodText(for tier: SubscriptionTier) -> String {
        switch billing {
        case .yearly:
            return "yıllık \(annualTotalText(for: tier))"
        case .monthly:
            return "aylık fatura"
        }
    }

    private func annualTotalText(for tier: SubscriptionTier) -> String {
        let fallback = planDisplay(for: tier)
        if let package = package(for: tier, billing: .yearly) {
            return package.price
        }
        return Self.currency(fallback.yearlyPrice)
    }

    private func monthlyTotalText(for tier: SubscriptionTier) -> String {
        let fallback = planDisplay(for: tier)
        if let package = package(for: tier, billing: .monthly) {
            return package.price
        }
        return Self.currency(fallback.monthlyPrice)
    }

    private static func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₺"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "₺\(value)"
    }
}

private enum PaywallBilling: String, Equatable {
    case yearly
    case monthly

    var title: String {
        switch self {
        case .yearly: return "Yıllık"
        case .monthly: return "Aylık"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .yearly: return "Yıllık abonelik"
        case .monthly: return "Aylık abonelik"
        }
    }
}

private struct PaywallPlanDisplay {
    let yearlyMonthlyPrice: Double
    let monthlyPrice: Double
    let yearlyPrice: Double
    let trialDays: Int?
    let features: [String]
}

private extension SubscriptionPlanPackage {
    func matches(_ billing: PaywallBilling) -> Bool {
        let token = [
            id,
            productIdentifier,
            title,
            subtitle
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
        .lowercased(with: Locale(identifier: "tr_TR"))

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

#Preview {
    PaywallView(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
