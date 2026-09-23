#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

/// Entry point for the pilot bundles: the Nova onboarding funnel for someone
/// new, the Nova sign-in surface for anyone who has finished the funnel or has
/// ever been signed in on this device. A signed-in user never reaches this
/// gate — AppState routes them to the app. Production keeps
/// `OnboardingViewV2` / `AuthView`; this file is compiled only into the
/// `NOVA_PILOT_BUILD` debug bundles.
struct NovaPilotEntryGate: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("nova.pilot.onboarding.completed.v1") private var onboardingCompleted = false
    /// Read once when the gate appears: a sign-up finishing inside the funnel
    /// must not swap the funnel for the login screen halfway through.
    @State private var returningUser = UserDefaults.standard.bool(forKey: Self.returningUserKey)
    @State private var showLogin = false
    @State private var appleService = AppleSignInService()
    @State private var googleService = GoogleSignInService()

    private static let returningUserKey = "nova.pilot.ever.authenticated.v1"

    /// Mirrors Android's `AppBootstrapStore.markAuthenticated`: once a session
    /// has existed here, a signed-out launch goes to login, not onboarding.
    static func markReturningUser() {
        UserDefaults.standard.set(true, forKey: returningUserKey)
    }

    private var showsLogin: Bool { onboardingCompleted || returningUser || showLogin }

    var body: some View {
        Group {
            if showsLogin {
                NovaLoginScreen(auth: bridge)
            } else {
                NovaOnboardingFlow(auth: bridge, onOpenLogin: { openLogin() })
            }
        }
        .onDisappear { app.novaPilotOnboardingActive = false }
    }

    private func openLogin() {
        app.novaPilotOnboardingActive = false
        showLogin = true
    }

    /// Runs an auth step the funnel started. Only then does the new session
    /// keep the user in the funnel (trial and push screens still follow); a
    /// session from anywhere else — a restored one, the login screen — sends
    /// the user straight into the app.
    private func funnelAuth(_ step: () async throws -> Void) async throws {
        let inFunnel = !showsLogin
        if inFunnel { app.novaPilotOnboardingActive = true }
        do {
            try await step()
        } catch {
            if inFunnel { app.novaPilotOnboardingActive = false }
            throw error
        }
    }

    private var bridge: NovaOBAuthBridge {
        NovaOBAuthBridge(
            signIn: { email, password in
                try await app.auth.signInWithPassword(email: email, password: password)
                await app.auth.refreshProfile()
            },
            signUp: { email, password in
                try await funnelAuth { try await app.auth.signUpWithPassword(email: email, password: password) }
            },
            sendCode: { email in
                try await app.auth.sendEmailOTP(email: email)
            },
            verifyCode: { email, code in
                try await funnelAuth { try await app.auth.verifyEmailOTP(email: email, token: code) }
                await app.auth.refreshProfile()
            },
            recoverPassword: { email in
                try await app.auth.requestPasswordRecovery(email: email)
            },
            appleSignIn: {
                let result = try await appleService.signIn()
                try await funnelAuth {
                    try await app.auth.signInWithApple(
                        idToken: result.idToken, nonce: result.nonce,
                        email: result.email, fullName: result.fullName
                    )
                }
                await app.auth.refreshProfile()
            },
            googleSignIn: {
                let result = try await googleService.signIn()
                try await funnelAuth {
                    try await app.auth.signInWithGoogle(
                        idToken: result.idToken, accessToken: result.accessToken, nonce: result.nonce,
                        emailFallback: result.email, fullNameFallback: result.fullName
                    )
                }
                await app.auth.refreshProfile()
            },
            requestPush: {
                await NotificationService.shared.requestPermissionAndRegisterFromOnboarding()
            },
            saveDraft: { answers in
                // Stored locally now; AppState's session observer syncs it the
                // moment the account exists.
                OnboardingAnswersService.shared.savePendingDraft(answers.makeDraft())
            },
            finish: { answers in
                if let answers {
                    OnboardingAnswersService.shared.savePendingDraft(answers.makeDraft())
                }
                onboardingCompleted = true
                app.novaPilotOnboardingActive = false
                if app.auth.isAuthenticated {
                    Task { await OnboardingAnswersService.shared.syncPendingDraftIfPossible() }
                    app.signIn()
                } else {
                    showLogin = true
                }
            }
        )
    }
}
#endif
