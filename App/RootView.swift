import SwiftUI

struct RootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var app: AppState
    @EnvironmentObject private var network: NetworkMonitor
    @StateObject private var legalDocuments = LegalDocumentService.shared
    @State private var appleSignInService = AppleSignInService()
    @State private var selectedLegalDocument: LegalDocumentKind?
    private let googleSignInService = GoogleSignInService()

    var body: some View {
        ZStack(alignment: .top) {
            Color.rdPaper.ignoresSafeArea()

            switch app.flow {
            case .splash:
                SplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingViewV2(
                    appLanguage: app.languagePreference,
                    initialSafetyProfileID: app.languagePreference == .english
                        ? app.safetyProfileID
                        : .turkeyCurrentV1,
                    isAuthenticated: app.isAuthenticated,
                    hasCompletedOnboarding: app.hasSeenOnboarding,
                    currentTier: app.currentTier,
                    subscriptionPackages: app.subscriptionPackages,
                    subscriptionOfferingsLoadState: app.subscriptionOfferingsLoadState,
                    onFinish: { app.finishOnboarding() },
                    onAuthApple: { runAppleSignIn() },
                    onAuthGoogle: { runGoogleSignIn() },
                    onAuthEmail: {},
                    onSignInExisting: {},
                    onPurchase: { plan in try await purchaseOnboardingPlan(plan) },
                    onReloadSubscriptionOfferings: { await app.refreshSubscriptionOfferings() },
                    onRestorePurchases: { try await restoreOnboardingPurchases() },
                    onSafetyProfileChange: { app.setSafetyProfile($0) }
                )
                    .transition(.opacity)
            case .auth:
                AuthView()
                    .transition(.opacity)
            case .main:
                NovaPilotMainGate(auth: app.auth)
                    .transition(.opacity)
            }

            if Self.isUITestLaunch {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("root.\(flowIdentifier)")
            }

            if app.flow != .splash && !network.isOnline {
                OfflineStatusBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(200)
            }

            if let notice = legalDocuments.pendingBanner, app.flow == .main {
                LegalUpdateBanner(
                    notice: notice,
                    onReview: {
                        selectedLegalDocument = notice.primaryKind
                        Task { await legalDocuments.recordSeen(notice, userID: app.auth.session?.user.id) }
                    },
                    onDismiss: {
                        Task { await legalDocuments.recordSeen(notice, userID: app.auth.session?.user.id) }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, network.isOnline ? 10 : 64)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(210)
                .task(id: notice.id) {
                    await legalDocuments.recordPresented(
                        notice,
                        userID: app.auth.session?.user.id
                    )
                }
            }

            if case let .soft(policy) = app.releaseUpdateRequirement {
                AppReleaseSoftUpdateBanner(
                    policy: policy,
                    onUpdate: { openURL(policy.appStoreURL) },
                    onDismiss: { app.dismissSoftReleaseNotice() }
                )
                .padding(.horizontal, 16)
                .padding(.top, softUpdateTopPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(240)
            }

            if case let .hard(policy) = app.releaseUpdateRequirement {
                AppReleaseRequiredView(
                    policy: policy,
                    currentVersion: AppClientMetadata.appVersion,
                    currentBuild: AppClientMetadata.appBuild,
                    onUpdate: { openURL(policy.appStoreURL) }
                )
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .modifier(RootFlowAnimationModifier(flow: app.flow, isOnline: network.isOnline))
        .task {
            await refreshLegalDocuments()
            await app.refreshReleasePolicy()
        }
        .onChange(of: app.flow) { _ in
            Task { await refreshLegalDocuments() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task {
                    await refreshLegalDocuments()
                    await app.refreshReleasePolicy()
                }
            }
        }
        .sheet(item: $selectedLegalDocument) { kind in
            LegalInfoSheet(initialDocument: kind) {
                selectedLegalDocument = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(app.themePreference.colorScheme)
        }
        .sheet(item: $legalDocuments.pendingDecision) { notice in
            LegalUpdateDecisionSheet(
                notice: notice,
                onReview: {
                    // LegalUpdateDecisionSheet opens the in-app reader inside its own sheet stack.
                },
                onContinue: {
                    Task {
                        await legalDocuments.recordContinuedAcceptance(notice, userID: app.auth.session?.user.id)
                    }
                },
                onExplicitAccept: {
                    Task {
                        await legalDocuments.recordExplicitAcceptance(notice, userID: app.auth.session?.user.id)
                    }
                },
                onClose: {
                    Task {
                        await legalDocuments.dismiss(notice, userID: app.auth.session?.user.id)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(
                notice.changeType == .materialTerms
                    || notice.changeType == .materialPrivacy
            )
            .preferredColorScheme(app.themePreference.colorScheme)
        }
    }

    private func refreshLegalDocuments() async {
        #if DEBUG
        guard !Self.isUITestLaunch else { return }
        #endif
        await legalDocuments.refreshIfNeeded(
            userID: app.auth.session?.user.id,
            userCreatedAt: app.auth.session?.user.createdAt
        )
    }

    private var flowIdentifier: String {
        switch app.flow {
        case .splash: return "splash"
        case .onboarding: return "onboarding"
        case .auth: return "auth"
        case .main: return "main"
        }
    }

    private var softUpdateTopPadding: CGFloat {
        var padding: CGFloat = 10
        if app.flow != .splash && !network.isOnline {
            padding += 54
        }
        if legalDocuments.pendingBanner != nil && app.flow == .main {
            padding += 54
        }
        return padding
    }

    private static var isUITestLaunch: Bool {
        #if DEBUG
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
        #else
        false
        #endif
    }

    private func runAppleSignIn() {
        Task {
            do {
                let result = try await appleSignInService.signIn()
                try await app.auth.signInWithApple(
                    idToken: result.idToken,
                    nonce: result.nonce,
                    email: result.email,
                    fullName: result.fullName
                )
                await app.auth.refreshProfile()
            } catch {
                guard !isUserCancelledAuth(error) else { return }
                let message = AppErrorMessage.make(
                    error,
                    context: RDLocalization.string("localizable.root.view.apple.ile.giris.yapilamadi.21368868", table: .localizable, fallback: "Apple ile giriş yapılamadı"),
                    fallbackTitle: RDLocalization.string("localizable.root.view.apple.ile.giris.yapilamadi.a6d8a45e", table: .localizable, fallback: "Apple ile giriş yapılamadı")
                )
                AuthService.logAuthError(message, operation: "apple_sign_in")
                app.authError = message.message
            }
        }
    }

    private func runGoogleSignIn() {
        Task {
            do {
                let result = try await googleSignInService.signIn()
                try await app.auth.signInWithGoogle(
                    idToken: result.idToken,
                    accessToken: result.accessToken,
                    nonce: result.nonce,
                    emailFallback: result.email,
                    fullNameFallback: result.fullName
                )
                await app.auth.refreshProfile()
            } catch {
                guard !isUserCancelledAuth(error) else { return }
                let message = AppErrorMessage.make(
                    error,
                    context: RDLocalization.string("localizable.root.view.google.ile.giris.yapilamadi.b2fcab5f", table: .localizable, fallback: "Google ile giriş yapılamadı"),
                    fallbackTitle: RDLocalization.string("localizable.root.view.google.ile.giris.yapilamadi.dcbd9e22", table: .localizable, fallback: "Google ile giriş yapılamadı")
                )
                AuthService.logAuthError(message, operation: "google_sign_in")
                app.authError = message.message
            }
        }
    }

    private func purchaseOnboardingPlan(_ plan: OBPlan) async throws {
        if app.subscriptionPackages.isEmpty {
            await app.refreshSubscriptionOfferings()
        }
        guard let package = onboardingPackage(for: plan) else {
            throw NSError(
                domain: "RiskDetected.OnboardingPurchase",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("localizable.root.view.secilen.abonelik.paketi.su.an.hazirlanamadi.lutf.c748fe84", table: .localizable, fallback: "Seçilen abonelik paketi şu an hazırlanamadı. Lütfen birazdan tekrar dene.")]
            )
        }
        try await app.purchaseSubscription(packageID: package.id, expectedTier: .plus)
    }

    private func restoreOnboardingPurchases() async throws -> Bool {
        let restoredState = try await app.restoreSubscriptions()
        return restoredState.tier.isPaid
    }

    private func onboardingPackage(for plan: OBPlan) -> SubscriptionPlanPackage? {
        app.subscriptionPackages
            .filter { $0.tier == .plus }
            .first { package in
                package.matchesOnboardingBilling(plan) && package.displayPrice != nil
            }
    }

    private func isUserCancelledAuth(_ error: Error) -> Bool {
        let nsError = error as NSError
        let lower = error.localizedDescription.lowercased(with: .autoupdatingCurrent)
        return nsError.code == 1 && nsError.domain.contains("WebAuthenticationSession") ||
            lower.contains("cancel") ||
            lower.contains("vazgeç") ||
            lower.contains("canceled") ||
            lower.contains("cancelled") ||
            lower.contains("authentication session error 1") ||
            lower.contains("webauthenticationsession")
    }
}

private struct OfflineStatusBanner: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "wifi.slash")
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdCriticalText)

            Text(RDLocalization.string("localizable.root.view.cevrimdisisin.bazi.veriler.son.kayitli.haliyle.g.08875828", table: .localizable, fallback: "Çevrimdışısın. Bazı veriler son kayıtlı haliyle görünebilir."))
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdCritical.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.rdOnyx.opacity(0.12), radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("network.offline_banner")
    }
}

private struct LegalUpdateBanner: View {
    let notice: LegalUpdateNotice
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(notice.message)
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(RDLocalization.string("localizable.root.view.incele.1d16e710", table: .localizable, fallback: "İncele"), action: onReview)
                .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdGreen.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.rdOnyx.opacity(0.12), radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("legal.update.banner")
    }
}

private struct AppReleaseSoftUpdateBanner: View {
    let policy: AppReleasePolicy
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.app.fill")
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdPlanPlusDark)

            VStack(alignment: .leading, spacing: 2) {
                Text(RDLocalization.string("localizable.root.view.yeni.surum.hazir.6c683226", table: .localizable, fallback: "Yeni sürüm hazır"))
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(policy.displayMessage)
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdCharcoal)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(RDLocalization.string("localizable.root.view.guncelle.b2397c17", table: .localizable, fallback: "Güncelle"), action: onUpdate)
                .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdPlanPlusDark)
                .buttonStyle(.plain)
                .accessibilityIdentifier("app_release.soft_update.update")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RDLocalization.string("localizable.root.view.daha.sonra.f6df34f8", table: .localizable, fallback: "Daha sonra"))
            .accessibilityIdentifier("app_release.soft_update.dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.rdPlanPlusSoft)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdPlanPlus.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.rdPlanPlus.opacity(0.16), radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("app_release.soft_update")
    }
}

private struct AppReleaseRequiredView: View {
    let policy: AppReleasePolicy
    let currentVersion: String
    let currentBuild: String
    let onUpdate: () -> Void

    var body: some View {
        ZStack {
            Color.rdPaper.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(RDTypography.font(size: RDFontScale.size(34), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdPlanPlusDark)
                        .frame(width: 76, height: 76)
                        .background(Color.rdPlanPlusSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.rdPlanPlus.opacity(0.36), lineWidth: 1)
                        )

                    Text(RDLocalization.string("localizable.root.view.guncelleme.gerekli.ed75982f", table: .localizable, fallback: "Güncelleme gerekli"))
                        .font(RDTypography.font(size: RDFontScale.size(27), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .multilineTextAlignment(.center)

                    Text(policy.displayMessage)
                        .font(RDTypography.font(size: RDFontScale.size(15), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdCharcoal)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Text(RDLocalization.string("localizable.root.view.mevcut.surum.4acd53ed", table: .localizable, fallback: "Mevcut sürüm"))
                        .foregroundStyle(Color.rdSlate)
                    Text("\(currentVersion) (\(currentBuild))")
                        .foregroundStyle(Color.rdBlack)
                }
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Color.rdWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 13))

                Button(action: onUpdate) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text(RDLocalization.string("localizable.root.view.app.store.da.guncelle.93093aa7", table: .localizable, fallback: "App Store'da güncelle"))
                    }
                    .font(RDTypography.font(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.rdOnyx)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Color.rdOnyx.opacity(0.18), radius: 18, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("app_release.hard_update.button")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 34)
        }
        .accessibilityIdentifier("app_release.hard_update")
    }
}

private struct LegalUpdateDecisionSheet: View {
    let notice: LegalUpdateNotice
    let onReview: () -> Void
    let onContinue: () -> Void
    let onExplicitAccept: () -> Void
    let onClose: () -> Void
    @State private var selectedLegalDocument: LegalDocumentKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.changeType == .explicitConsent ? "checkmark.shield.fill" : "doc.text.fill")
                    .font(RDTypography.font(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 38, height: 38)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(notice.title)
                        .font(RDTypography.font(size: RDFontScale.size(19), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(notice.message)
                        .font(RDTypography.font(size: RDFontScale.size(13), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                onReview()
                selectedLegalDocument = notice.primaryKind
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(RDLocalization.string("localizable.root.view.guncel.metinleri.incele.7f371307", table: .localizable, fallback: "Güncel metinleri incele"))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.rdWhite)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if notice.changeType == .explicitConsent {
                RDButton(title: RDLocalization.string("localizable.root.view.kabul.ediyorum.bad1103d", table: .localizable, fallback: "Kabul ediyorum"), style: .primary, icon: "checkmark.shield.fill") {
                    onExplicitAccept()
                }
                Button(RDLocalization.string("localizable.root.view.simdilik.kapat.9e0bc284", table: .localizable, fallback: "Şimdilik kapat"), action: onClose)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
            } else {
                RDButton(title: RDLocalization.string("localizable.root.view.devam.et.3ce8f48e", table: .localizable, fallback: "Devam et"), style: .primary, icon: "checkmark") {
                    onContinue()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.rdPaper)
        .accessibilityIdentifier("legal.update.decision_sheet")
        .sheet(item: $selectedLegalDocument) { kind in
            LegalInfoSheet(initialDocument: kind) {
                selectedLegalDocument = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

extension SubscriptionPlanPackage {
    func matchesOnboardingBilling(_ plan: OBPlan) -> Bool {
        let token = [
            id,
            productIdentifier
        ]
        .joined(separator: " ")
        .lowercased(with: Locale(identifier: "en_US"))

        switch plan {
        case .yearly:
            return token.contains("annual") ||
                token.contains("year") ||
                token.contains("yearly")
        case .monthly:
            return token.contains("monthly") ||
                token.contains("month")
        }
    }
}

private struct RootFlowAnimationModifier: ViewModifier {
    let flow: AppFlow
    let isOnline: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        if Self.isUITestLaunch {
            content
        } else {
            content
                .animation(.easeInOut(duration: 0.32), value: flow)
                .animation(.easeInOut(duration: 0.22), value: isOnline)
        }
        #else
        content
            .animation(.easeInOut(duration: 0.32), value: flow)
            .animation(.easeInOut(duration: 0.22), value: isOnline)
        #endif
    }

    #if DEBUG
    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }
    #endif
}

struct SplashView: View {
    var body: some View {
        ZStack {
            RDLogo(size: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
        .environmentObject(NetworkMonitor.shared)
}
