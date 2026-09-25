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
    /// Nova pages size their top and bottom padding from the screen insets, so they
    /// wait one layout pass for the measurement.
    @State private var insetsMeasured = false

    var body: some View {
        Group {
            if !insetsMeasured {
                NovaOB.surface.ignoresSafeArea()
            } else if showsLogin {
                NovaLoginScreen(auth: bridge)
            } else {
                NovaOnboardingFlow(auth: bridge, onOpenLogin: { openLogin() })
            }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
            NovaOB.screenInsets = insets
            insetsMeasured = true
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
        #if targetEnvironment(simulator)
        if CommandLine.arguments.contains("RD_UI_TEST_NOVA_AUTH_STUB") { return Self.uiTestAuth }
        #endif
        return NovaOBAuthBridge(
            signIn: { email, password in
                do { try await app.auth.signInWithPassword(email: email, password: password) }
                catch { throw AuthService.passwordSignInFailure(error) }
                await app.auth.refreshProfile()
            },
            signUp: { email, password in
                try await funnelAuth { try await app.auth.signUpWithPassword(email: email, password: password) }
            },
            resendSignupCode: { email in
                try await app.auth.resendSignupCode(email: email)
            },
            verifySignupCode: { email, code, password in
                do {
                    try await funnelAuth {
                        try await app.auth.verifySignupCode(email: email, token: code, password: password)
                    }
                } catch { throw AuthService.codeCheckFailure(error) }
                await app.auth.refreshProfile()
            },
            recoverPassword: { email in
                try await app.auth.requestPasswordRecovery(email: email)
            },
            verifyRecoveryCode: { email, code in
                // Holds AppState's routing the way the funnel does: the recovery session
                // must not open the app before the new password is set.
                app.novaPilotOnboardingActive = true
                do { try await app.auth.verifyRecoveryCode(email: email, token: code) }
                catch {
                    app.novaPilotOnboardingActive = false
                    throw AuthService.codeCheckFailure(error)
                }
            },
            setNewPassword: { password in
                try await app.auth.setNewPassword(password)
            },
            finishRecovery: {
                app.novaPilotOnboardingActive = false
                Self.markReturningUser()
                await app.auth.refreshProfile()
                app.signIn()
            },
            cancelRecovery: {
                try? await app.auth.signOut()
                app.novaPilotOnboardingActive = false
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
            saveDraft: { draft in
                // Stored locally now; AppState's session observer syncs it the
                // moment the account exists.
                OnboardingAnswersService.shared.savePendingDraft(draft)
            },
            finish: { draft in
                if let draft {
                    OnboardingAnswersService.shared.savePendingDraft(draft)
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

    #if targetEnvironment(simulator)
    /// UI tests on the real sign-in surface, without the network. `exists@example.com`
    /// has an account, so a password sign-in is refused as a wrong password and signup
    /// reports the account; any other address has none and signs up. A code starting with
    /// `0` is refused, `999999` fails as a lost connection, and any other six digits verify.
    private static let uiTestAuth = NovaOBAuthBridge(
        signIn: { _, _ in throw IsgPasswordAuthError.invalidCredentials },
        signUp: { email, _ in if email == "exists@example.com" { throw IsgPasswordAuthError.accountExists } },
        resendSignupCode: { _ in },
        verifySignupCode: { _, code, _ in try uiTestCheck(code) },
        recoverPassword: { _ in },
        verifyRecoveryCode: { _, code in try uiTestCheck(code) },
        setNewPassword: { _ in }, finishRecovery: {}, cancelRecovery: {},
        appleSignIn: {}, googleSignIn: {}, requestPush: {},
        saveDraft: { _ in }, finish: { _ in })

    private static func uiTestCheck(_ code: String) throws {
        if code == "999999" { throw URLError(.notConnectedToInternet) }
        if code.hasPrefix("0") { throw NSError(domain: "NovaUITestAuth", code: 403) }
    }
    #endif
}
#endif
