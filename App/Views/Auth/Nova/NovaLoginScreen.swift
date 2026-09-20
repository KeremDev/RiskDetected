#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

/// `İSGADA Giriş.dc.html` — one surface for sign-in and sign-up: providers on
/// top, mail below. A known address signs straight in; an unknown one opens the
/// verification sheet, exactly as the prototype describes.
struct NovaLoginScreen: View {
    let auth: NovaOBAuthBridge
    var onBack: (() -> Void)? = nil

    @State private var phase: Phase = .form
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var error = ""
    @State private var busy = false
    @State private var digits = Array(repeating: "", count: 6)
    @State private var codeVerified = false
    @State private var resendNote = ""
    @State private var resetBusy = false
    @State private var resetSent = false
    @State private var doneKind: DoneKind = .login
    @State private var logoShown = false
    @FocusState private var focus: Field?

    private enum Phase: Equatable { case form, sheet, forgot, done }
    private enum DoneKind { case login, signup }
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            NovaOB.surface.ignoresSafeArea()
            switch phase {
            case .form, .sheet: formScreen
            case .forgot: forgotScreen
            case .done: doneScreen
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.24), value: phase)
    }

    // MARK: form

    private var formScreen: some View {
        ZStack {
            NovaOBFittedScroll {
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
                            Text("Giriş yap ya da saniyeler içinde hesabını oluştur. Ayrı bir kayıt adımı yok.")
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
            }

            if phase == .sheet { verificationSheet }
        }
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
                .buttonStyle(.plain)
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

            Button { phase = .forgot; error = ""; resetSent = false } label: {
                Text("Şifremi unuttum")
                    .font(NovaOB.font(14.5, 600))
                    .foregroundColor(NovaOB.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private var eyeIcon: some View {
        NovaOBIconPath(
            path: showPassword
                ? "M2.4 12S6 5.6 12 5.6 21.6 12 21.6 12 18 18.4 12 18.4 2.4 12 2.4 12z|circle:12,12,3.1"
                : "M2.4 12S6 5.6 12 5.6 21.6 12 21.6 12 18 18.4 12 18.4 2.4 12 2.4 12z|circle:12,12,3.1|M4 20L20 4",
            size: 20, color: showPassword ? NovaOB.ink : NovaOB.muted, lineWidth: 1.7
        )
    }

    // MARK: verification sheet

    private var verificationSheet: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { phase = .form; codeVerified = false }

            VStack(spacing: 16) {
                Capsule().fill(NovaOB.line).frame(width: 44, height: 5)

                HStack(alignment: .top, spacing: 12) {
                    NovaOBAnimatedLock(tint: NovaOB.ink, bodyColor: NovaOB.ink, keyholeColor: .white)
                        .frame(width: 40, height: 40)
                        .background(NovaOB.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Doğrulama").font(NovaOB.font(21, 700)).tracking(-0.3)
                        Text("\(email.novaTrimmed.isEmpty ? "E-posta" : email.novaTrimmed) adresine gönderdiğimiz doğrulama kodunu gir.")
                            .font(NovaOB.font(14.5))
                            .foregroundColor(NovaOB.muted)
                            .lineSpacing(NovaOB.lineSpacing(14.5, 1.4))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { phase = .form; codeVerified = false } label: {
                        NovaOBIconPath(path: "M6 6l12 12|M18 6L6 18", size: 13, color: NovaOB.ink, lineWidth: 2.4)
                            .frame(width: 34, height: 34)
                            .background(NovaOB.fill2, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                NovaOBCodeField(digits: $digits, state: error.isEmpty ? (codeVerified ? .verified : .idle) : .invalid) { code in
                    Task { await verify(code) }
                }

                if codeVerified {
                    NovaOBInfoNote(
                        text: "Kod doğrulandı, hesabın oluşturuluyor…",
                        icon: "circle:12,12,9.2|M7.8 12.3l2.9 2.9 5.5-6"
                    )
                } else {
                    HStack(spacing: 12) {
                        Button { Task { await resend() } } label: {
                            HStack(spacing: 7) {
                                NovaOBIconPath(path: "M20 11a8 8 0 10-2.6 5.9|M20 4.5V11h-6",
                                               size: 14, color: NovaOB.ink, lineWidth: 1.9)
                                Text("Yeniden gönder").font(NovaOB.font(13, 600)).foregroundColor(NovaOB.ink)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                        Text(resendNote.isEmpty ? "Kod gelmediyse spam klasörünü kontrol et." : resendNote)
                            .font(NovaOB.font(12))
                            .foregroundColor(NovaOB.muted2)
                            .multilineTextAlignment(.trailing)
                            .lineSpacing(NovaOB.lineSpacing(12, 1.35))
                    }
                }

                if !error.isEmpty { NovaOBErrorNote(text: error) }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
            .background(
                NovaOB.surface,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .shadow(color: .black.opacity(0.18), radius: 20, y: -12)
            .transition(.move(edge: .bottom))
        }
        .animation(.timingCurve(0.2, 0.85, 0.25, 1, duration: 0.34), value: phase)
    }

    // MARK: forgot

    private var forgotScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            NovaOBBackButton { phase = .form; error = ""; resetSent = false }
                .padding(.leading, -10)

            VStack(spacing: 14) {
                NovaOBIconPath(
                    path: "M8.1 11.4V8.5a3.9 3.9 0 017.8 0|M4.6 11.2h14.8v9.6H4.6z|circle:12,16,1.5",
                    size: 26, color: NovaOB.ink, lineWidth: 2
                )
                .frame(width: 60, height: 60)
                .background(NovaOB.fill2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 7) {
                    Text("Şifreni sıfırlayalım")
                        .font(NovaOB.font(26, 700))
                        .tracking(-0.4)
                        .lineSpacing(NovaOB.lineSpacing(26, 1.18))
                    Text("Kayıtlı e-posta adresini yaz; sıfırlama bağlantısını hemen gönderelim.")
                        .font(NovaOB.font(15.5))
                        .foregroundColor(NovaOB.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 296)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    NovaOBIconPath(path: "M2.5 4.5h19v15h-19z|M3 7l9 6 9-6", size: 19,
                                   color: NovaOB.muted2, lineWidth: 1.7)
                        .padding(.leading, 16)
                    TextField("E-posta adresin", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .padding(.leading, 8)
                }
                .novaOBField(leadingInset: 0, border: focus == .email ? NovaOB.ink : NovaOB.line)

                if !error.isEmpty { NovaOBErrorNote(text: error) }
                if resetSent {
                    NovaOBInfoNote(
                        text: "\(email.novaTrimmed.isEmpty ? "Adresin" : email.novaTrimmed) ile kayıtlı bir hesap varsa sıfırlama bağlantısını gönderdik.",
                        icon: "circle:12,12,9.2|M7.8 12.3l2.9 2.9 5.5-5.9"
                    )
                }

                NovaOBOutlineButton(
                    title: resetBusy ? "Gönderiliyor" : (resetSent ? "Tekrar gönder" : "Sıfırlama bağlantısı gönder"),
                    busy: resetBusy
                ) {
                    focus = nil
                    Task { await submitReset() }
                }
                .padding(.top, 2)

                Button { phase = .form; error = ""; resetSent = false } label: {
                    Text("Girişe dön")
                        .font(NovaOB.font(14.5, 600))
                        .foregroundColor(NovaOB.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 9) {
                NovaOBIconPath(path: "circle:12,12,9.2|M12 11v5.2|M12 7.8v.1", size: 15,
                               color: NovaOB.muted2, lineWidth: 1.8)
                    .padding(.top, 1)
                Text("Bağlantı 30 dakika geçerlidir. Apple veya Google ile giriş yaptıysan şifre gerekmez.")
                    .font(NovaOB.font(12.5))
                    .foregroundColor(NovaOB.muted)
                    .lineSpacing(NovaOB.lineSpacing(12.5, 1.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(NovaOB.fill3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 24)
        .padding(.top, NovaOB.padTop(56))
        .padding(.bottom, NovaOB.padBottom(28))
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
                Text(doneKind == .login ? "Tekrar hoş geldin" : "Hesabın hazır")
                    .font(NovaOB.font(26, 700))
                    .tracking(-0.4)
                Text(doneKind == .login
                     ? "Giriş yaptın. Çalışma alanın olduğu gibi duruyor."
                     : "Hesabını oluşturduk. Kurulumu uygulama içinde tamamlayacaksın.")
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
                self.error = AppErrorMessage.make(
                    error, context: "Giriş yapılamadı", fallbackTitle: "Giriş yapılamadı"
                ).message
            }
        }
        busy = false
    }

    /// Known address signs in; anything else gets a verification code, which is
    /// how the prototype splits "kayıtlı kullanıcı" from "yeni kullanıcı".
    private func submitMail() async {
        guard !busy else { return }
        let address = email.novaTrimmed.lowercased()
        guard NovaOBController.isValidEmail(address) else {
            error = "Geçerli bir e-posta adresi yaz."
            return
        }
        guard password.count >= 6 else {
            error = "Şifren en az 6 karakter olmalı."
            return
        }
        busy = true
        error = ""
        do {
            try await auth.signIn(address, password)
            doneKind = .login
            phase = .done
        } catch {
            do {
                try await auth.sendCode(address)
                digits = Array(repeating: "", count: 6)
                codeVerified = false
                phase = .sheet
            } catch {
                self.error = AppErrorMessage.make(
                    error, context: "Doğrulama kodu gönderilemedi", fallbackTitle: "Kod gönderilemedi"
                ).message
            }
        }
        busy = false
    }

    private func verify(_ code: String) async {
        error = ""
        do {
            try await auth.verifyCode(email.novaTrimmed.lowercased(), code)
            codeVerified = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            doneKind = .signup
            phase = .done
        } catch {
            codeVerified = false
            digits = Array(repeating: "", count: 6)
            self.error = "Geçersiz kod. Kodu kontrol edip yeniden dene."
        }
    }

    private func resend() async {
        do {
            try await auth.sendCode(email.novaTrimmed.lowercased())
            digits = Array(repeating: "", count: 6)
            resendNote = "Yeni kod gönderildi."
        } catch {
            resendNote = "Kod gönderilemedi, tekrar dene."
        }
    }

    private func submitReset() async {
        guard !resetBusy else { return }
        let address = email.novaTrimmed.lowercased()
        guard NovaOBController.isValidEmail(address) else {
            error = "Geçerli bir e-posta adresi yaz."
            resetSent = false
            return
        }
        resetBusy = true
        error = ""
        resetSent = false
        do {
            try await auth.recoverPassword(address)
            resetSent = true
        } catch {
            self.error = AppErrorMessage.make(
                error, context: "Sıfırlama bağlantısı gönderilemedi", fallbackTitle: "Bağlantı gönderilemedi"
            ).message
        }
        resetBusy = false
    }
}
#endif
