import SwiftUI

struct RootView: View {
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
                    isAuthenticated: app.isAuthenticated,
                    hasCompletedOnboarding: app.hasSeenOnboarding,
                    currentTier: app.currentTier,
                    subscriptionPackages: app.subscriptionPackages,
                    onFinish: { app.finishOnboarding() },
                    onAuthApple: { runAppleSignIn() },
                    onAuthGoogle: { runGoogleSignIn() },
                    onAuthEmail: {},
                    onSignInExisting: {},
                    onPurchase: { plan in try await purchaseOnboardingPlan(plan) },
                    onRestorePurchases: { try await restoreOnboardingPurchases() }
                )
                    .transition(.opacity)
            case .auth:
                AuthView()
                    .transition(.opacity)
            case .main:
                MainTabView()
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
            }
        }
        .animation(.easeInOut(duration: 0.32), value: app.flow)
        .animation(.easeInOut(duration: 0.22), value: network.isOnline)
        .task {
            await refreshLegalDocuments()
        }
        .onChange(of: app.flow) { _ in
            Task { await refreshLegalDocuments() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await refreshLegalDocuments() }
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
            .presentationDetents([.height(notice.changeType == .explicitConsent ? 360 : 320), .medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(notice.changeType == .materialTerms)
            .preferredColorScheme(app.themePreference.colorScheme)
        }
    }

    private func refreshLegalDocuments() async {
        await legalDocuments.refreshIfNeeded(userID: app.auth.session?.user.id)
    }

    private var flowIdentifier: String {
        switch app.flow {
        case .splash: return "splash"
        case .onboarding: return "onboarding"
        case .auth: return "auth"
        case .main: return "main"
        }
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
                    context: "Apple ile giriş yapılamadı",
                    fallbackTitle: "Apple ile giriş yapılamadı"
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
                    context: "Google ile giriş yapılamadı",
                    fallbackTitle: "Google ile giriş yapılamadı"
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
                userInfo: [NSLocalizedDescriptionKey: "Seçilen abonelik paketi şu an hazırlanamadı. Lütfen birazdan tekrar dene."]
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
                package.matchesOnboardingBilling(plan)
            }
    }

    private func isUserCancelledAuth(_ error: Error) -> Bool {
        let nsError = error as NSError
        let lower = error.localizedDescription.lowercased(with: Locale(identifier: "tr_TR"))
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
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdCriticalText)

            Text("Çevrimdışısın. Bazı veriler son kayıtlı haliyle görünebilir.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(notice.message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button("İncele", action: onReview)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
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
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 38, height: 38)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(notice.title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(notice.message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
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
                    Text("Güncel metinleri incele")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
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
                RDButton(title: "Kabul ediyorum", style: .primary, icon: "checkmark.shield.fill") {
                    onExplicitAccept()
                }
                Button("Şimdilik kapat", action: onClose)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
            } else {
                RDButton(title: "Devam et", style: .primary, icon: "checkmark") {
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
