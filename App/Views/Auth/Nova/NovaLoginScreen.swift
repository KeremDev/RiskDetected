#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

/// `İSGADA Giriş.dc.html` — providers on top, mail and password below. "Mail ile devam et"
/// signs an existing account straight in and answers a wrong password on this page; an
/// address without an account signs up with the same password and gets its code on its own
/// page. "Hesap oluştur" opens the signup page for the same result. A reset mails a code,
/// then asks for the new password.
struct NovaLoginScreen: View {
    let auth: NovaOBAuthBridge
    var onBack: (() -> Void)? = nil

    @State private var phase: Phase = .form
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var error = ""
    @State private var busy = false
    @State private var signupPassword = ""
    @State private var showSignupPassword = false
    @State private var digits = Array(repeating: "", count: 6)
    @State private var codeVerified = false
    @State private var codeError = ""
    /// `codeError` is a lost connection, not a wrong code.
    @State private var codeRetryable = false
    @State private var codeChecking = false
    @State private var resendNote = ""
    /// Where the signup code page's back button leads: the signup page, or sign-in.
    @State private var codeReturn: Phase = .signup
    /// The password typed for the signup the code page confirms.
    @State private var codePassword = ""
    @State private var newPassword = ""
    @State private var showNewPassword = false
    @State private var doneKind: DoneKind = .login
    @State private var logoShown = false
    @State private var pageHeight: CGFloat = 0
    @FocusState private var focus: Field?

    private enum Phase: Equatable { case form, signup, code, forgot, resetCode, newPassword, done }
    private enum DoneKind { case login, signup, reset }
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            NovaOB.surface.ignoresSafeArea()
            switch phase {
            case .form: formScreen
            case .signup: signupScreen
            case .code: codeScreen
            case .forgot: forgotScreen
            case .resetCode: resetCodeScreen
            case .newPassword: newPasswordScreen
            case .done: doneScreen
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.24), value: phase)
    }

    // MARK: form

    private var formScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    Image("NovaOBLogo")
                        .resizable().scaledToFit()
                        .frame(width: 168)
                        .padding(.top, 28)
                        .padding(.bottom, 56)
                        .scaleEffect(logoShown ? 1 : 0.7)
                        .opacity(logoShown ? 1 : 0)
                        .onAppear {
                            withAnimation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.42)) { logoShown = true }
                        }

                    VStack(spacing: 7) {
                        Text("Hoş geldin")
                            .font(NovaOB.font(28, 700))
                            .tracking(-0.5)
                            .lineSpacing(NovaOB.lineSpacing(28, 1.15))
                        Text("Giriş yap ya da saniyeler içinde hesabını oluştur.")
                            .font(NovaOB.font(15.5))
                            .foregroundColor(NovaOB.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 290)
                    }
                }

                NovaOBProviderButtons(
                    onApple: { Task { await runProvider(auth.appleSignIn) } },
                    onGoogle: { Task { await runProvider(auth.googleSignIn) } }
                )
                .padding(.top, 4)

                NovaOBDivider(text: "veya mail ile").padding(.vertical, 2)

                credentials

                Spacer(minLength: 20)

                NovaOBLegalLine(prefix: "Devam ederek", alignment: .center)
            }
            .padding(.horizontal, 24)
            .padding(.top, NovaOB.padTop(64))
            .padding(.bottom, NovaOB.padBottom(28))
            .frame(minHeight: pageHeight, alignment: .top)
        }
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
    }

    private var credentials: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                NovaOBIconPath(path: "M2.5 4.5h19v15h-19z|M3 7.5l9 6 9-6", size: 19,
                               color: NovaOB.muted2, lineWidth: 1.7)
                    .padding(.leading, 16)
                TextField("E-posta adresin", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .focused($focus, equals: .email)
                    .padding(.leading, 8)
            }
            .novaOBField(leadingInset: 0, border: focus == .email ? NovaOB.ink : NovaOB.line)

            HStack(spacing: 0) {
                NovaOBIconPath(path: "M4 10.5h16v10.5H4z|M8 10.5V7.5a4 4 0 018 0v3", size: 19,
                               color: NovaOB.muted2, lineWidth: 1.7)
                    .padding(.leading, 16)
                Group {
                    if showPassword {
                        TextField("Şifren", text: $password)
                    } else {
                        SecureField("Şifren", text: $password)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .padding(.leading, 8)

                Button { showPassword.toggle() } label: {
                    eyeIcon
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(NovaPressStyle())
                .padding(.trailing, 6)
            }
            .novaOBField(leadingInset: 0, trailingInset: 0,
                         border: focus == .password ? NovaOB.ink : NovaOB.line)

            if !error.isEmpty { NovaOBErrorNote(text: error) }

            NovaOBOutlineButton(
                title: busy ? "Kontrol ediliyor" : "Mail ile devam et",
                busy: busy,
                icon: AnyView(
                    NovaOBIconPath(path: "M2.5 4.5h19v15h-19z|M3 7.5l9 6 9-6", size: 20,
                                   color: NovaOB.ink, lineWidth: 1.8)
                )
            ) {
                focus = nil
                Task { await submitMail() }
            }

            Button { openForgot() } label: {
                Text("Şifreni bilmiyor musun?")
                    .font(NovaOB.font(14.5, 600))
                    .foregroundColor(NovaOB.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(NovaPressStyle())

            Button { openSignup() } label: {
                (Text("Hesabın yok mu? ").foregroundColor(NovaOB.muted)
                 + Text("Hesap oluştur").foregroundColor(NovaOB.ink))
                    .font(NovaOB.font(14.5, 600))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(NovaPressStyle())
            .accessibilityIdentifier("nova.login.signup")
        }
    }

    // MARK: signup and code

    private var signupScreen: some View {
        NovaOBSignupPage(
            email: $email, password: $signupPassword, showPassword: $showSignupPassword,
            error: error, busy: busy,
            onBack: backToForm, onLogin: backToForm,
            onSubmit: { Task { await submitSignup() } }
        )
    }

    private var codeScreen: some View {
        NovaOBCodePage(
            email: email, digits: $digits, error: codeError, retryable: codeRetryable,
            checking: codeChecking, verified: codeVerified,
            verifiedNote: "Kod doğrulandı, hesabın oluşturuluyor…", resendNote: resendNote,
            onBack: { error = ""; phase = codeReturn },
            onEdit: clearCodeError,
            onComplete: { code in Task { await verify(code) } },
            onResend: { Task { await resend() } }
        )
    }

    private var resetCodeScreen: some View {
        NovaOBCodePage(
            email: email, digits: $digits, error: codeError, retryable: codeRetryable,
            checking: codeChecking, verified: codeVerified,
            verifiedNote: "Kod doğrulandı.", resendNote: resendNote,
            onBack: { phase = .forgot },
            onEdit: clearCodeError,
            onComplete: { code in Task { await verifyReset(code) } },
            onResend: { Task { await resendReset() } }
        )
    }

    private var newPasswordScreen: some View {
        NovaOBNewPasswordPage(
            password: $newPassword, showPassword: $showNewPassword,
            error: error, busy: busy,
            onBack: {
                // The code opened a session; leaving without a new password ends it.
                Task { await auth.cancelRecovery() }
                backToForm()
            },
            onSubmit: { Task { await saveNewPassword() } }
        )
    }

    private var eyeIcon: some View {
        NovaOBIconPath(
            path: showPassword
                ? "M2.4 12S6 5.6 12 5.6 21.6 12 21.6 12 18 18.4 12 18.4 2.4 12 2.4 12z|circle:12,12,3.1"
                : "M2.4 12S6 5.6 12 5.6 21.6 12 21.6 12 18 18.4 12 18.4 2.4 12 2.4 12z|circle:12,12,3.1|M4 20L20 4",
            size: 20, color: showPassword ? NovaOB.ink : NovaOB.muted, lineWidth: 1.7
        )
    }

    // MARK: forgot

    private var forgotScreen: some View {
        NovaOBResetEmailPage(
            email: $email, error: error, busy: busy,
            onBack: backToForm,
            onSubmit: { Task { await submitReset() } }
        )
    }

    // MARK: done

    private var doneScreen: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image("NovaOBLogo").resizable().scaledToFit().frame(width: 120)
            NovaOBIconPath(path: "M5 12.6l4.4 4.4L19 7", size: 38, color: .white, lineWidth: 2.2)
                .frame(width: 78, height: 78)
                .background(NovaOB.ink, in: Circle())
            VStack(spacing: 8) {
                Text(doneTitle)
                    .font(NovaOB.font(26, 700))
                    .tracking(-0.4)
                Text(doneNote)
                    .font(NovaOB.font(15.5))
                    .foregroundColor(NovaOB.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
            }
            HStack(spacing: 9) {
                NovaOBSpinner(size: 15)
                Text("Uygulamaya yönlendiriliyorsun…")
                    .font(NovaOB.font(13.5))
                    .foregroundColor(NovaOB.muted2)
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
    }

    private var doneTitle: String {
        switch doneKind {
        case .login: return "Tekrar hoş geldin"
        case .signup: return "Hesabın hazır"
        case .reset: return "Şifren kaydedildi"
        }
    }

    private var doneNote: String {
        switch doneKind {
        case .login: return "Giriş yaptın. Çalışma alanın olduğu gibi duruyor."
        case .signup: return "Hesabını oluşturduk. Kurulumu uygulama içinde tamamlayacaksın."
        case .reset: return "Yeni şifrenle giriş yaptın. Sonraki girişlerinde bu şifreyi kullan."
        }
    }

    // MARK: actions

    private func runProvider(_ operation: @escaping () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        error = ""
        do {
            try await operation()
            doneKind = .login
            phase = .done
        } catch {
            if !NovaOBController.isCancellation(error) {
                NovaHaptics.failure()
                self.error = AppErrorMessage.make(
                    error, context: "Giriş yapılamadı", fallbackTitle: "Giriş yapılamadı"
                ).message
            }
        }
        busy = false
    }

    static let wrongPasswordMessage =
        "Şifren yanlış. Şifreni bilmiyorsan aşağıdan kodla yenisini belirleyebilirsin. Apple veya Google ile kaydolduysan o butonla giriş yap."
    static let passwordRulesMessage = "Şifre en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."

    /// "Mail ile devam et": an existing account signs in, a new address signs up with the
    /// same password and gets its code. Supabase answers a wrong password and an unknown
    /// address the same way, so a refused sign-in tries signup, which reports an existing
    /// account without sending mail. Every password account was made under
    /// `IsgPasswordRules`, so a password that breaks them is refused here, before any request.
    private func submitMail() async {
        guard !busy else { return }
        let address = email.novaTrimmed.lowercased()
        guard NovaOBController.isValidEmail(address) else {
            fail("Geçerli bir e-posta adresi yaz.")
            return
        }
        guard !password.isEmpty else {
            fail("Şifreni yaz.")
            return
        }
        guard IsgPasswordRules(password).valid else {
            fail(Self.passwordRulesMessage)
            return
        }
        busy = true
        error = ""
        do {
            try await auth.signIn(address, password)
            doneKind = .login
            phase = .done
        } catch IsgPasswordAuthError.invalidCredentials {
            await signUpFromForm(address)
        } catch IsgPasswordAuthError.emailNotConfirmed {
            // The account was created but its code never entered: finish the signup.
            let sent = (try? await auth.resendSignupCode(address)) != nil
            openCode(returningTo: .form, password: password)
            if !sent { resendNote = "Kod gönderilemedi. Bir dakika sonra tekrar dene." }
        } catch {
            fail(AppErrorMessage.make(error, context: "Giriş yapılamadı", fallbackTitle: "Giriş yapılamadı").message)
        }
        busy = false
    }

    private func signUpFromForm(_ address: String) async {
        do {
            try await auth.signUp(address, password)
            openCode(returningTo: .form, password: password)
        } catch IsgPasswordAuthError.confirmationRequired {
            openCode(returningTo: .form, password: password)
        } catch IsgPasswordAuthError.accountExists {
            fail(Self.wrongPasswordMessage)
        } catch {
            fail(AppErrorMessage.make(error, context: "Giriş yapılamadı", fallbackTitle: "Giriş yapılamadı").message)
        }
    }

    private func fail(_ message: String) {
        NovaHaptics.failure()
        error = message
    }

    private func openSignup() {
        error = ""
        signupPassword = ""
        focus = nil
        phase = .signup
    }

    private func backToForm() {
        error = ""
        phase = .form
    }

    private func submitSignup() async {
        guard !busy else { return }
        let address = email.novaTrimmed.lowercased()
        guard NovaOBController.isValidEmail(address) else {
            NovaHaptics.failure()
            error = "Geçerli bir e-posta adresi yaz."
            return
        }
        guard IsgPasswordRules(signupPassword).valid else {
            NovaHaptics.failure()
            error = "Parola en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."
            return
        }
        busy = true
        error = ""
        do {
            try await auth.signUp(address, signupPassword)
            openCode(returningTo: .signup, password: signupPassword)
        } catch IsgPasswordAuthError.confirmationRequired {
            openCode(returningTo: .signup, password: signupPassword)
        } catch IsgPasswordAuthError.accountExists {
            NovaHaptics.failure()
            error = NovaOBController.accountExistsMessage
        } catch {
            NovaHaptics.failure()
            self.error = AppErrorMessage.make(
                error, context: "Hesap oluşturulamadı", fallbackTitle: "Hesap oluşturulamadı"
            ).message
        }
        busy = false
    }

    private func openCode(returningTo previous: Phase, password: String) {
        resetCodeState()
        codeReturn = previous
        codePassword = password
        phase = .code
    }

    private func resetCodeState() {
        digits = Array(repeating: "", count: 6)
        codeVerified = false
        codeChecking = false
        clearCodeError()
        resendNote = ""
    }

    private func clearCodeError() {
        codeError = ""
        codeRetryable = false
    }

    /// A refused code keeps its digits, so one wrong box can be fixed and checked again.
    private func showCodeFailure(_ error: Error) {
        NovaHaptics.failure()
        codeVerified = false
        codeRetryable = NovaOBController.isConnectionFailure(error)
        codeError = codeRetryable ? NovaOBController.codeConnectionMessage : NovaOBController.codeRejectedMessage
    }

    private func verify(_ code: String) async {
        guard !codeChecking, !codeVerified else { return }
        codeChecking = true
        clearCodeError()
        do {
            try await auth.verifySignupCode(email.novaTrimmed.lowercased(), code, codePassword)
            NovaHaptics.success()
            codeVerified = true
            codeChecking = false
            try? await Task.sleep(nanoseconds: 900_000_000)
            doneKind = .signup
            phase = .done
        } catch {
            codeChecking = false
            showCodeFailure(error)
        }
    }

    private func resend() async {
        do {
            try await auth.resendSignupCode(email.novaTrimmed.lowercased())
            digits = Array(repeating: "", count: 6)
            clearCodeError()
            resendNote = "Yeni kod gönderildi."
        } catch {
            resendNote = "Kod gönderilemedi. Bir dakika sonra tekrar dene."
        }
    }

    // MARK: reset

    private func openForgot() {
        error = ""
        focus = nil
        phase = .forgot
    }

    private func submitReset() async {
        guard !busy else { return }
        let address = email.novaTrimmed.lowercased()
        guard NovaOBController.isValidEmail(address) else {
            fail("Geçerli bir e-posta adresi yaz.")
            return
        }
        busy = true
        error = ""
        do {
            try await auth.recoverPassword(address)
            resetCodeState()
            phase = .resetCode
        } catch {
            fail("Kod gönderilemedi. Bir dakika sonra tekrar dene.")
        }
        busy = false
    }

    private func verifyReset(_ code: String) async {
        guard !codeChecking, !codeVerified else { return }
        codeChecking = true
        clearCodeError()
        do {
            try await auth.verifyRecoveryCode(email.novaTrimmed.lowercased(), code)
            NovaHaptics.success()
            codeVerified = true
            codeChecking = false
            try? await Task.sleep(nanoseconds: 700_000_000)
            newPassword = ""
            error = ""
            phase = .newPassword
        } catch {
            codeChecking = false
            showCodeFailure(error)
        }
    }

    private func resendReset() async {
        do {
            try await auth.recoverPassword(email.novaTrimmed.lowercased())
            digits = Array(repeating: "", count: 6)
            clearCodeError()
            resendNote = "Yeni kod gönderildi."
        } catch {
            resendNote = "Kod gönderilemedi. Bir dakika sonra tekrar dene."
        }
    }

    private func saveNewPassword() async {
        guard !busy else { return }
        guard IsgPasswordRules(newPassword).valid else {
            fail(Self.passwordRulesMessage)
            return
        }
        busy = true
        error = ""
        do {
            try await auth.setNewPassword(newPassword)
        } catch IsgPasswordAuthError.samePassword {
            // Already the account's password: the reset has what it wanted.
        } catch {
            fail("Şifre kaydedilemedi. Bağlantını kontrol edip yeniden dene.")
            busy = false
            return
        }
        NovaHaptics.success()
        doneKind = .reset
        phase = .done
        busy = false
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await auth.finishRecovery()
    }
}
#endif
