import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject private var network: NetworkMonitor
    @State private var appleSignInService = AppleSignInService()
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
                    isAuthenticated: app.auth.isAuthenticated,
                    currentTier: app.currentTier,
                    onFinish: { app.finishOnboarding() },
                    onAuthApple: { runAppleSignIn() },
                    onAuthGoogle: { runGoogleSignIn() },
                    onAuthEmail: {},
                    onSignInExisting: {},
                    onPurchase: { plan, complete in purchaseOnboardingPlan(plan, onComplete: complete) },
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
        }
        .animation(.easeInOut(duration: 0.32), value: app.flow)
        .animation(.easeInOut(duration: 0.22), value: network.isOnline)
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
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
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

    private func purchaseOnboardingPlan(_ plan: OBPlan, onComplete: @escaping () -> Void) {
        Task {
            do {
                if app.subscriptionPackages.isEmpty {
                    await app.refreshSubscriptionOfferings()
                }
                guard let package = onboardingPackage(for: plan) else {
                    app.authError = "Seçilen abonelik paketi şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene."
                    return
                }
                try await app.purchaseSubscription(packageID: package.id)
                onComplete()
            } catch is CancellationError {
                return
            } catch {
                app.authError = AppErrorMessage.make(
                    error,
                    context: "Abonelik başlatılamadı",
                    fallbackTitle: "Abonelik başlatılamadı"
                ).message
            }
        }
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

private extension SubscriptionPlanPackage {
    func matchesOnboardingBilling(_ plan: OBPlan) -> Bool {
        let token = [
            id,
            productIdentifier,
            title,
            subtitle
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
        .lowercased(with: Locale(identifier: "tr_TR"))

        switch plan {
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
