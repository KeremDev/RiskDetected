import SwiftUI

enum PaywallPresentationStyle {
    case standard
    case plusFocused
}

struct PaywallView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil
    var layout: PaywallPresentationStyle = .standard

    @State private var selectedTier: SubscriptionTier = .plus
    @State private var billing: PaywallBilling = .yearly
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showStandardPaywall = false

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

                if layout == .plusFocused {
                    paywallContent(width: contentWidth)
                        .padding(.horizontal, 20)
                        .frame(width: proxy.size.width, alignment: .top)
                } else {
                    ScrollView(showsIndicators: false) {
                        paywallContent(width: contentWidth)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 188)
                    }
                    .frame(width: proxy.size.width)
                }

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
            if layout == .plusFocused {
                selectedTier = .plus
            } else if app.currentTier == .plus {
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
        .fullScreenCover(isPresented: $showStandardPaywall) {
            PaywallView(
                onClose: { showStandardPaywall = false },
                onSubscribe: {
                    showStandardPaywall = false
                    onSubscribe()
                },
                layout: .standard
            )
            .environmentObject(app)
        }
    }

    private func paywallContent(width contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: layout == .plusFocused ? 7 : 8) {
            Color.clear
                .frame(height: layout == .plusFocused ? 90 : 118)

            paywallHeadline
                .padding(.bottom, layout == .plusFocused ? 8 : 0)

            billingToggle

            if let notice {
                noticeCard(notice)
            }

            Color.clear.frame(height: layout == .plusFocused ? 6 : 12)

            planOptions

            if let errorMessage {
                noticeCard(errorMessage)
            }

            if let packageLoadError {
                noticeCard(packageLoadError)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
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

    private var paywallHeadline: some View {
        VStack(spacing: 6) {
            Text("İş Güvenliği Uzmanlarının Tercihi")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(onyx)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text("İSG Raporunu Dakikalar İçinde Hazırla")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(graphite.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.68),
                                Color.white.opacity(0.42),
                                greenSoft.opacity(0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.82),
                                green.opacity(0.34),
                                Color.white.opacity(0.46)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.white.opacity(0.72), radius: 14, x: 0, y: 0)
            .shadow(color: green.opacity(0.10), radius: 18, x: 0, y: 8)
        )
        .padding(.horizontal, 8)
        .shadow(color: Color.white.opacity(0.86), radius: 4, x: 0, y: 1)
        .accessibilityElement(children: .combine)
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
                .padding(.top, layout == .plusFocused ? 8 : 10)

                giftBadge
                    .position(x: proxy.size.width * 0.28, y: layout == .plusFocused ? 8 : 10)
            }
        }
        .frame(height: layout == .plusFocused ? 46 : 52)
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
            .frame(height: layout == .plusFocused ? 34 : 38)
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
        .padding(.horizontal, layout == .plusFocused ? 10 : 12)
        .frame(height: layout == .plusFocused ? 26 : 28)
        .background(green)
        .clipShape(Capsule())
        .shadow(color: green.opacity(0.32), radius: 10, x: 0, y: 4)
        .opacity(billing == .yearly ? 1 : 0.0)
        .animation(.easeInOut(duration: 0.18), value: billing)
    }

    @ViewBuilder
    private var planOptions: some View {
        switch layout {
        case .standard:
            HStack(alignment: .top, spacing: 10) {
                paidPlanCard(.plus, recommended: true)
                paidPlanCard(.pro, recommended: false)
            }
        case .plusFocused:
            VStack(alignment: .leading, spacing: 10) {
                paidPlanCard(.plus, recommended: true)
                proExploreLink
            }
        }
    }

    private var proExploreLink: some View {
        Button {
            showStandardPaywall = true
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Text("Pro'yu incele")
                        .font(.system(size: 12.5, weight: .black, design: .rounded))
                    planIcon(for: .pro, size: 11)
                }
                .foregroundStyle(onyx.opacity(0.9))

                Text("Daha yüksek limitler ve özellikler")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(slate.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .background(Color.white.opacity(0.56))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(line.opacity(0.78), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pro'yu incele, klasik paywall ekranını aç")
    }

    private func paidPlanCard(_ tier: SubscriptionTier, recommended: Bool) -> some View {
        let selected = selectedTier == tier
        let display = planDisplay(for: tier)
        let current = app.currentTier == tier
        let isPlusFocusedCard = layout == .plusFocused && tier == .plus
        let cardMinHeight: CGFloat? = isPlusFocusedCard ? nil : 286

        return Button {
            selectedTier = tier
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(alignment: isPlusFocusedCard ? .center : .leading, spacing: isPlusFocusedCard ? 7 : 5) {
                HStack(alignment: .center, spacing: 7) {
                    radio(checked: selected, size: 19)

                    Text(tier.title)
                        .font(.system(size: isPlusFocusedCard ? 21 : 18, weight: .black, design: .rounded))
                        .foregroundStyle(onyx)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    planIcon(for: tier, size: isPlusFocusedCard ? 15 : 13)
                }
                .frame(maxWidth: .infinity, alignment: isPlusFocusedCard ? .center : .leading)

                VStack(alignment: isPlusFocusedCard ? .center : .leading, spacing: isPlusFocusedCard ? 4 : 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(pricePerMonthText(for: tier))
                            .font(.system(size: isPlusFocusedCard ? 30 : 22, weight: .black, design: .rounded))
                            .foregroundStyle(onyx)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text("/ay")
                            .font(.system(size: isPlusFocusedCard ? 13 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(slate)
                    }

                    Text(periodText(for: tier))
                        .font(.system(size: isPlusFocusedCard ? 12 : 10, weight: .medium, design: .rounded))
                        .foregroundStyle(slate)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: isPlusFocusedCard ? .center : .leading)

                if let trialDays = display.trialDays {
                    trialChip(days: trialDays)
                } else {
                    Color.clear.frame(height: 22)
                }

                Rectangle()
                    .fill(line)
                    .frame(height: 1)
                    .padding(.vertical, isPlusFocusedCard ? 2 : 0)

                if isPlusFocusedCard {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(stride(from: 0, to: display.features.count, by: 2)), id: \.self) { index in
                            compactFeatureRow(
                                left: display.features[index],
                                right: index + 1 < display.features.count ? display.features[index + 1] : nil
                            )
                        }
                    }
                    .frame(maxWidth: 326, alignment: .leading)
                    .padding(.top, 1)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(display.features, id: \.self) { feature in
                            featureLine(feature)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !isPlusFocusedCard {
                    Spacer(minLength: 0)
                }

                if current {
                    currentPlanPill
                }
            }
            .padding(isPlusFocusedCard ? 13 : 10)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: isPlusFocusedCard ? .top : .topLeading)
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

    private func planIcon(for tier: SubscriptionTier, size: CGFloat) -> some View {
        Image(systemName: tier.badgeIcon)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(tier.accentColor)
            .accessibilityHidden(true)
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
        .foregroundStyle(Color(hex: "#7A4300"))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#FFE28A"),
                    Color(hex: "#FFC94A")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.62), lineWidth: 1))
        .shadow(color: Color(hex: "#F2B400").opacity(0.28), radius: 8, x: 0, y: 3)
    }

    private func featureLine(_ text: String, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: prominent ? 9 : 6) {
            Image(systemName: "checkmark")
                .font(.system(size: prominent ? 13 : 10, weight: .black, design: .rounded))
                .foregroundStyle(green)
                .frame(width: prominent ? 16 : 12)

            Text(text)
                .font(.system(size: prominent ? 14 : 10, weight: .semibold, design: .rounded))
                .foregroundStyle(graphite)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
    }

    private func compactFeatureRow(left: String, right: String?) -> some View {
        HStack(spacing: 8) {
            compactFeatureLine(left)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let right {
                Rectangle()
                    .fill(line)
                    .frame(width: 1, height: 18)

                compactFeatureLine(right)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func compactFeatureLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(green)
                .frame(width: 12)

            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(graphite)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
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

            Button {
                onClose()
            } label: {
                Text("Ücretsiz devam et")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(slate.opacity(0.78))
            }
            .buttonStyle(.plain)

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
        return Color.white
    }

    private var primaryButtonBackground: Color {
        if selectedTier.isPaid && selectedPackage == nil && packageLoadError != nil { return green }
        if selectedTier.isPaid && selectedPackage == nil { return cloud }
        if selectedTier.isPaid && app.currentTier == selectedTier { return cloud }
        return green
    }

    private var primaryButtonDisabled: Bool {
        isWorking ||
            (selectedTier.isPaid && selectedPackage == nil && packageLoadError == nil) ||
            (selectedTier.isPaid && app.currentTier == selectedTier)
    }

    private var legalese: String {
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
                let restoredState = try await app.restoreSubscriptions()
                isWorking = false
                if restoredState.tier.isPaid {
                    onSubscribe()
                } else {
                    errorMessage = "Geri yüklenecek aktif abonelik bulunamadı."
                }
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
                    "10/gün Analiz",
                    "PDF/Excel Rapor",
                    "Fine-Kinney Risk Analizi",
                    "5*5 Matris Risk Analizi",
                    "Gelişmiş Odak Analizi",
                    "Mail ve Whatsapp ile Paylaşım",
                    "Özelleştirilebilir Raporlar"
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
            if let monthlyEquivalentPrice = selectedPackage.monthlyEquivalentPrice,
               !Self.shouldUseTRYFallback(for: monthlyEquivalentPrice) {
                return monthlyEquivalentPrice
            }
            return Self.shouldUseTRYFallback(for: selectedPackage.price)
                ? Self.currency(fallback.yearlyMonthlyPrice)
                : selectedPackage.price
        }
        return Self.shouldUseTRYFallback(for: selectedPackage.price)
            ? Self.currency(fallback.monthlyPrice)
            : selectedPackage.price
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
            return Self.shouldUseTRYFallback(for: package.price) ? Self.currency(fallback.yearlyPrice) : package.price
        }
        return Self.currency(fallback.yearlyPrice)
    }

    private func monthlyTotalText(for tier: SubscriptionTier) -> String {
        let fallback = planDisplay(for: tier)
        if let package = package(for: tier, billing: .monthly) {
            return Self.shouldUseTRYFallback(for: package.price) ? Self.currency(fallback.monthlyPrice) : package.price
        }
        return Self.currency(fallback.monthlyPrice)
    }

    private static func shouldUseTRYFallback(for price: String) -> Bool {
        let locale = Locale.current
        guard locale.region?.identifier == "TR" else { return false }

        let normalized = price
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .uppercased(with: Locale(identifier: "en_US"))
        return normalized.contains("$") || normalized.contains("USD")
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
