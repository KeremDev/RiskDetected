import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var app: AppState

    var onClose: () -> Void
    var onSubscribe: () -> Void
    var notice: String? = nil

    @State private var selectedTier: SubscriptionTier = .plus
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let paidTiers: [SubscriptionTier] = [.plus, .pro]
    private let allTiers: [SubscriptionTier] = [.free, .plus, .pro]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.rdWhite.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if let notice {
                        noticeCard(notice)
                    }
                    planComparison
                    packageSelector
                    if let errorMessage {
                        noticeCard(errorMessage)
                    }
                    ctaButton
                    legalRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 24)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Color.rdBlack)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .task {
            await app.refreshSubscriptionOfferings()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                RDTierBadge(tier: .plus)
                RDTierBadge(tier: .pro)
            }
            Text("Saha risk analizini planına göre büyüt.")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .fixedSize(horizontal: false, vertical: true)
            Text("Free haklarını gör, Plus veya Pro ile detaylı analiz, rapor ve gelişmiş canvasları aç.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planComparison: some View {
        VStack(spacing: 10) {
            ForEach(allTiers, id: \.self) { tier in
                planCard(tier)
            }
        }
    }

    private func planCard(_ tier: SubscriptionTier) -> some View {
        let capabilities = PlanCapabilities.forTier(tier)
        let current = app.currentTier == tier
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(tier.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                        if tier.isPaid {
                            RDTierBadge(tier: tier, small: true)
                        }
                    }
                    Text(priceText(for: tier))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                Spacer()
                if current {
                    Text("Mevcut plan")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tier.accentTextColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(tier.accentSoftColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if tier.isPaid {
                    Image(systemName: selectedTier == tier ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedTier == tier ? tier.accentColor : Color.rdSlate.opacity(0.35))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                featureRow("Analiz", capabilities.standardAnalysisLabel)
                featureRow("Detaylı analiz", capabilities.detailedAnalysisLabel)
                featureRow("Rapor", capabilities.reportLabel)
                featureRow("Hızlandırılmış", capabilities.acceleratedReportLabel)
                featureRow("Arşiv", capabilities.archiveLabel)
                featureRow("Risk tablosu", capabilities.canUseDetailedRiskTable ? "Açık" : "Kapalı")
                featureRow("AI canvas", capabilities.advancedCanvasLabel)
                featureRow("Otomatik gönderim", capabilities.canUseAutomaticDelivery ? "Açık" : "Kapalı")
                featureRow("Destek", capabilities.supportLabel)
            }
        }
        .padding(16)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor(for: tier, current: current), lineWidth: selectedTier == tier ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            guard tier.isPaid else { return }
            selectedTier = tier
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private var packageSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ABONELİK")
                .rdMono(size: 11, weight: .bold)
                .foregroundStyle(Color.rdSlate)
            ForEach(packages(for: selectedTier)) { package in
                Button {
                    selectedTier = package.tier
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: package.tier.badgeIcon)
                            .foregroundStyle(package.tier.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(package.subtitle)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                        }
                        Spacer()
                        Text(package.price)
                            .rdMono(size: 16, weight: .bold)
                            .foregroundStyle(Color.rdBlack)
                    }
                    .padding(14)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ctaButton: some View {
        RDButton(
            title: isWorking ? "İşleniyor..." : "\(selectedTier.title)'a Geç",
            style: .detect,
            trailingIcon: "arrow.right",
            height: 56
        ) {
            purchaseSelectedPlan()
        }
        .disabled(isWorking || selectedPackage == nil)
        .opacity(selectedPackage == nil ? 0.62 : 1)
    }

    private var legalRow: some View {
        HStack(spacing: 14) {
            Spacer()
            Button("Geri Yükle") { restore() }
                .buttonStyle(.plain)
            separator
            Text("Şartlar")
            separator
            Text("Gizlilik")
            Spacer()
        }
        .font(.system(size: 12, design: .rounded))
        .foregroundStyle(Color.rdSlate)
    }

    private func featureRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdCritical)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.rdCritical.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var separator: some View {
        Text("·").foregroundStyle(Color.rdSlate.opacity(0.6))
    }

    private var selectedPackage: SubscriptionPlanPackage? {
        packages(for: selectedTier).first
    }

    private func packages(for tier: SubscriptionTier) -> [SubscriptionPlanPackage] {
        app.subscriptionPackages.filter { $0.tier == tier }
    }

    private func priceText(for tier: SubscriptionTier) -> String {
        guard tier.isPaid else { return "Ücretsiz" }
        return packages(for: tier).first?.price ?? "RevenueCat'te yapılandırılıyor"
    }

    private func borderColor(for tier: SubscriptionTier, current: Bool) -> Color {
        if current { return tier.accentColor }
        if selectedTier == tier { return tier.accentColor }
        return Color.rdLine
    }

    private func purchaseSelectedPlan() {
        guard let selectedPackage else {
            errorMessage = "Bu plan için RevenueCat paketi bulunamadı."
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
}

#Preview {
    PaywallView(onClose: {}, onSubscribe: {})
        .environmentObject(AppState())
}
