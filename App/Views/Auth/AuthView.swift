import SwiftUI

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var phase: AuthPhase = .options
    @State private var email: String = ""
    @State private var code: [String] = Array(repeating: "", count: RDConfig.Auth.emailOTPLength)
    @State private var otpInput: String = ""
    @State private var authError: AppErrorMessage?
    @State private var isSendingEmailCode = false
    @State private var isVerifyingEmailCode = false
    @State private var isSigningInWithApple = false
    @State private var isSigningInWithGoogle = false
    @State private var appleSignInService = AppleSignInService()
    private let googleSignInService = GoogleSignInService()
    @State private var autoVerifiedCode: String?
    @State private var caretPulse = false
    @State private var selectedLegalDocument: LegalDocumentKind?
    @StateObject private var keyboard = KeyboardObserver()
    @FocusState private var focusedField: AuthInputField?

    enum AuthPhase { case options, email, otp }
    enum AuthInputField { case email, otp }

    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var otpCode: String { otpInput }
    private var canSendEmailCode: Bool { normalizedEmail.contains("@") && normalizedEmail.contains(".") && !isSendingEmailCode }
    private var canVerifyEmailCode: Bool { otpCode.count == RDConfig.Auth.emailOTPLength && !isVerifyingEmailCode }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // MARK: Full-screen hero photo
                Image("AuthHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()

                // MARK: Bottom gradient overlay (photo → paper)
                LinearGradient(
                    stops: [
                        .init(color: .clear,                           location: 0.0),
                        .init(color: .clear,                           location: 0.30),
                        .init(color: Color.rdGreenSoft.opacity(0.16),  location: 0.45),
                        .init(color: Color.rdPaper.opacity(0.28),      location: 0.58),
                        .init(color: Color.rdPaper.opacity(0.68),      location: 0.72),
                        .init(color: Color.rdPaper.opacity(0.94),      location: 0.86),
                        .init(color: Color.rdPaper,                    location: 0.96),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // MARK: Top gradient overlay (paper → clear) for status bar legibility
                LinearGradient(
                    stops: [
                        .init(color: Color.rdPaper.opacity(0.72),      location: 0.0),
                        .init(color: Color.rdPaper.opacity(0.30),      location: 0.06),
                        .init(color: .clear,                           location: 0.14),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // MARK: Identity + form — daha yukarıda dengeli blok
                let keyboardLift = max(0, keyboard.height - geo.safeAreaInsets.bottom)

                VStack(spacing: phase == .email ? 18 : 20) {
                    VStack(spacing: 10) {
                        RDLogo(size: phase == .email ? 36 : 38)
                        Text(RDLocalization.string("auth.auth.view.saha.icin.yapay.zeka.destekli.is.guvenligi.asist.73caffd7", table: .auth, fallback: "Saha için yapay zekâ destekli iş güvenliği asistanı"))
                            .font(RDTypography.font(size: RDFontScale.size(13), weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdGraphite)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 270)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.white.opacity(0.52), location: 0.22),
                                .init(color: Color.white.opacity(0.70), location: 0.50),
                                .init(color: Color.white.opacity(0.52), location: 0.78),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .blur(radius: 8)
                    }

                    form
                        .padding(.horizontal, 20)
                        .padding(.bottom, keyboardLift > 0 ? 0 : max(18, geo.safeAreaInsets.bottom))
                }
                .padding(.bottom, keyboardLift > 0 ? keyboardLift + 14 : max(22, geo.safeAreaInsets.bottom + 8))
                .offset(y: keyboardLift > 0 ? -8 : (phase == .email ? -24 : 0))
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.22), value: keyboard.height)
            }
        }
        .ignoresSafeArea()
        .background(Color.rdPaper)
        .accessibilityIdentifier("auth.root")
        .onChange(of: phase) { newPhase in
            if newPhase == .email {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    focusedField = .email
                }
            } else if newPhase == .otp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    focusedField = .otp
                }
                caretPulse = true
            } else {
                focusedField = nil
                caretPulse = false
            }
        }
        .onChange(of: focusedField) { field in
            caretPulse = field == .otp
        }
        .sheet(item: $selectedLegalDocument) { kind in
            LegalInfoSheet(initialDocument: kind) {
                selectedLegalDocument = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.light)
        }
    }

    // Form yüksekliği phase'e göre değişmez, badge pozisyonu için sabit referans
    private var formHeight: CGFloat {
        switch phase {
        case .options: return 326
        case .email:   return authError == nil ? 246 : 332
        case .otp:     return 280
        }
    }

    @ViewBuilder
    private var form: some View {
        switch phase {
        case .options: optionsForm
        case .email:   emailForm
        case .otp:     otpForm
        }
    }

    // MARK: - Options

    private var optionsForm: some View {
        VStack(spacing: 10) {
            emailSignInButton {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .email }
            }

            HStack(spacing: 12) {
                Rectangle().fill(Color.rdSlate.opacity(0.22)).frame(height: 1)
                Text(RDLocalization.string("auth.auth.view.veya.96cc844b", table: .auth, fallback: "veya"))
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdGraphite.opacity(0.78))
                    .padding(.horizontal, 4)
                Rectangle().fill(Color.rdSlate.opacity(0.22)).frame(height: 1)
            }
            .padding(.vertical, 2)

            RDButton(
                title: isSigningInWithApple ? RDLocalization.string("auth.auth.view.apple.ile.baglaniyor.0ea0accc", table: .auth, fallback: "Apple ile bağlanıyor...") : RDLocalization.string("auth.auth.view.apple.ile.devam.et.44a40f55", table: .auth, fallback: "Apple ile devam et"),
                style: .primary,
                icon: isSigningInWithApple ? "hourglass" : "applelogo",
                showsActionIcon: false
            ) {
                runAppleSignIn()
            }
            .disabled(isSigningInWithApple)
            .opacity(isSigningInWithApple ? 0.75 : 1)
            .accessibilityIdentifier("auth.apple")
            googleButton {
                runGoogleSignIn()
            }
            .disabled(isSigningInWithGoogle)
            .opacity(isSigningInWithGoogle ? 0.75 : 1)
            .accessibilityIdentifier("auth.google")

            legalNotice

            if let err = authError {
                Text(err.message)
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            if let svcErr = app.authError {
                Text("⚠️ \(svcErr)")
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func emailSignInButton(action: @escaping () -> Void) -> some View {
        let localizedTitle = RDLocalization.string(
            "auth.auth.view.e.posta.ile.giris.yap.ff1b3d8b",
            table: .auth,
            fallback: "E-posta ile giriş yap"
        )

        return Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(RDTypography.font(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)

                Text(localizedTitle)
                    .font(RDTypography.font(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdOnyx)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .padding(.horizontal, 18)
            .background(Color.rdWhite.opacity(0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.rdOnyx, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.rdOnyx.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedTitle)
        .accessibilityIdentifier("auth.email.start")
    }

    private func googleButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isSigningInWithGoogle {
                    Image(systemName: "hourglass")
                        .font(RDTypography.font(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                } else {
                    GoogleMark()
                        .frame(width: 22, height: 22)
                }

                if isSigningInWithGoogle {
                    Text(RDLocalization.string("auth.auth.view.google.ile.baglaniyor.d73e6d77", table: .auth, fallback: "Google ile bağlanıyor..."))
                        .font(RDTypography.font(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .tracking(-0.2)
                } else {
                    GoogleWordmark()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .padding(.horizontal, 18)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.rdOnyx, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.rdOnyx.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isSigningInWithGoogle
                ? RDLocalization.string("auth.auth.view.google.ile.baglaniyor.d73e6d77", table: .auth, fallback: "Google ile bağlanıyor...")
                : GoogleWordmark.localizedTitle
        )
    }

    private var legalNotice: some View {
        LegalAcceptanceNotice(
            fontSize: 10,
            textColor: Color.rdSlate,
            linkColor: Color.rdGreenDark,
            accessibilityIdentifier: "auth.legal_notice",
            onOpenDocument: { selectedLegalDocument = $0 }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var authErrorText: some View {
        if let err = authError {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdCritical)
                        .padding(.top, 1)

                    Text(err.message)
                        .font(RDTypography.font(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdCritical)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if phase == .otp {
                    Button {
                        resendEmailCode()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSendingEmailCode ? "hourglass" : "arrow.clockwise")
                                .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                            Text(isSendingEmailCode ? RDLocalization.string("auth.auth.view.yeni.kod.gonderiliyor.b1451c30", table: .auth, fallback: "Yeni kod gönderiliyor...") : RDLocalization.string("auth.auth.view.yeni.kod.gonder.7cb92f87", table: .auth, fallback: "Yeni kod gönder"))
                                .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.rdCritical)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSendingEmailCode)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rdCriticalBg.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.rdCritical.opacity(0.14), lineWidth: 1)
            )
        }
    }

    // MARK: - Email

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(RDLocalization.string("auth.auth.view.e.posta.adresinizi.giriniz.e6b9a429", table: .auth, fallback: "E-posta Adresinizi Giriniz"))
                .font(RDTypography.font(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            Color.rdPaper.opacity(0.68)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.74), lineWidth: 1)
                )
                .shadow(color: Color.white.opacity(0.7), radius: 10, x: 0, y: 0)
                .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(RDTypography.font(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdOnyx.opacity(0.82))
                    .frame(width: 54, height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                TextField(
                    "",
                    text: $email,
                    prompt: Text(RDLocalization.string("auth.auth.view.mailinizi.yaziniz.0b6f66bd", table: .auth, fallback: "Mailinizi yazınız..."))
                        .foregroundColor(Color.rdOnyx.opacity(0.34))
                )
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .font(RDTypography.font(size: RDFontScale.size(16), design: .rounded))
                    .foregroundColor(Color.rdOnyx)
                    .tint(Color.rdGreen)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RDButton(
                title: isSendingEmailCode ? RDLocalization.string("auth.auth.view.kod.gonderiliyor.726a039d", table: .auth, fallback: "Kod gönderiliyor...") : RDLocalization.string("auth.auth.view.kod.gonder.781cb25a", table: .auth, fallback: "Kod gönder"),
                style: .primary,
                trailingIcon: isSendingEmailCode ? "hourglass" : "arrow.right"
            ) {
                sendEmailCode()
            }
            .opacity(canSendEmailCode ? 1 : 0.55)
            .disabled(!canSendEmailCode)
            legalNotice
            authErrorText
            Button(RDLocalization.string("auth.auth.view.diger.giris.yontemleri.99e4376a", table: .auth, fallback: "← Diğer giriş yöntemleri")) {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .options }
            }
            .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
            .foregroundStyle(Color.rdInk)
            .frame(maxWidth: .infinity)
            .padding(8)
        }
    }

    // MARK: - OTP

    private var otpForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RDLocalization.string("auth.auth.view.dogrulama.kodu.95aeac29", table: .auth, fallback: "Doğrulama kodu"))
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.34), radius: 8, x: 0, y: 2)
                Text(RDLocalization.format("auth.auth.view.1.adresine.gonderildi.a08ac01d", table: .auth, fallback: "%1$@ adresine gönderildi", arguments: [String(describing: normalizedEmail.isEmpty ? "mail@ornek.com" : normalizedEmail)]))
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: Color.black.opacity(0.38), radius: 8, x: 0, y: 2)
            }
            ZStack {
                TextField("", text: $otpInput)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .otp)
                    .font(RDTypography.font(size: RDFontScale.size(1)))
                    .foregroundStyle(Color.clear)
                    .tint(Color.clear)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .opacity(0.01)
                    .onChange(of: otpInput) { newValue in
                        syncOTPInput(newValue)
                    }

                HStack(spacing: 10) {
                    ForEach(0..<RDConfig.Auth.emailOTPLength, id: \.self) { i in
                        otpDigitBox(index: i)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = .otp
            }

            Text(RDLocalization.string("auth.auth.view.kod.gelmedi.mi.e.posta.adresini.kontrol.edip.tek.b7b833bb", table: .auth, fallback: "Kod gelmedi mi? E-posta adresini kontrol edip tekrar gönderebilirsin."))
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .shadow(color: Color.black.opacity(0.34), radius: 8, x: 0, y: 2)

            RDButton(
                title: isVerifyingEmailCode ? RDLocalization.string("auth.auth.view.dogrulaniyor.1968dffd", table: .auth, fallback: "Doğrulanıyor...") : RDLocalization.string("auth.auth.view.dogrula.ve.giris.yap.b1c67bca", table: .auth, fallback: "Doğrula ve giriş yap"),
                style: .detect,
                icon: isVerifyingEmailCode ? "hourglass" : nil
            ) {
                verifyEmailCode()
            }
            .opacity(canVerifyEmailCode ? 1 : 0.55)
            .disabled(!canVerifyEmailCode)
            authErrorText

            Button(RDLocalization.string("auth.auth.view.e.posta.adresini.degistir.e85f01e6", table: .auth, fallback: "← E-posta adresini değiştir")) {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .email }
            }
            .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.94))
            .frame(maxWidth: .infinity)
            .padding(8)
            .shadow(color: Color.black.opacity(0.34), radius: 8, x: 0, y: 2)
        }
    }

    private func sendEmailCode() {
        guard canSendEmailCode else { return }
        requestEmailCode(transitionToOTP: true)
    }

    private func resendEmailCode() {
        guard !isSendingEmailCode else { return }
        requestEmailCode(transitionToOTP: false)
    }

    private func requestEmailCode(transitionToOTP: Bool) {
        isSendingEmailCode = true
        authError = nil
        Task {
            do {
                try await app.auth.sendEmailOTP(email: normalizedEmail)
                autoVerifiedCode = nil
                otpInput = ""
                code = Array(repeating: "", count: RDConfig.Auth.emailOTPLength)
                if transitionToOTP {
                    withAnimation(.easeInOut(duration: 0.22)) { phase = .otp }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    focusedField = .otp
                }
            } catch {
                setAuthError(error, context: RDLocalization.string("auth.auth.view.kod.gonderilemedi.50c44043", table: .auth, fallback: "Kod gönderilemedi"), fallbackTitle: RDLocalization.string("auth.auth.view.kod.gonderilemedi.50c44043", table: .auth, fallback: "Kod gönderilemedi"), operation: "send_email_otp", email: normalizedEmail)
            }
            isSendingEmailCode = false
        }
    }

    private func verifyEmailCode() {
        guard canVerifyEmailCode else { return }
        isVerifyingEmailCode = true
        authError = nil
        Task {
            do {
                try await app.auth.verifyEmailOTP(email: normalizedEmail, token: otpCode)
            } catch {
                setAuthError(error, context: RDLocalization.string("auth.auth.view.kod.dogrulanamadi.8919fbda", table: .auth, fallback: "Kod doğrulanamadı"), fallbackTitle: RDLocalization.string("auth.auth.view.kod.dogrulanamadi.8919fbda", table: .auth, fallback: "Kod doğrulanamadı"), operation: "verify_email_otp", email: normalizedEmail)
            }
            isVerifyingEmailCode = false
        }
    }

    private func runAppleSignIn() {
        guard !isSigningInWithApple else { return }
        isSigningInWithApple = true
        authError = nil
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
                if !isUserCancelledAuth(error) {
                    setAuthError(error, context: RDLocalization.string("auth.auth.view.apple.ile.giris.yapilamadi.8f8a40ac", table: .auth, fallback: "Apple ile giriş yapılamadı"), fallbackTitle: RDLocalization.string("auth.auth.view.apple.ile.giris.yapilamadi.8f8a40ac", table: .auth, fallback: "Apple ile giriş yapılamadı"), operation: "apple_sign_in")
                }
            }
            isSigningInWithApple = false
        }
    }

    private func runGoogleSignIn() {
        guard !isSigningInWithGoogle else { return }
        isSigningInWithGoogle = true
        authError = nil
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
                if !isUserCancelledAuth(error) {
                    setAuthError(error, context: RDLocalization.string("auth.auth.view.google.ile.giris.yapilamadi.28393332", table: .auth, fallback: "Google ile giriş yapılamadı"), fallbackTitle: RDLocalization.string("auth.auth.view.google.ile.giris.yapilamadi.28393332", table: .auth, fallback: "Google ile giriş yapılamadı"), operation: "google_sign_in")
                }
            }
            isSigningInWithGoogle = false
        }
    }

    private func setAuthError(
        _ error: Error,
        context: String,
        fallbackTitle: String,
        operation: String,
        email: String? = nil
    ) {
        let message = AppErrorMessage.make(error, context: context, fallbackTitle: fallbackTitle)
        AuthService.logAuthError(message, operation: operation, email: email)
        authError = message
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

    private func syncOTPInput(_ newValue: String) {
        let sanitized = String(newValue.filter(\.isNumber).prefix(RDConfig.Auth.emailOTPLength))
        if sanitized != otpInput {
            otpInput = sanitized
            return
        }

        var nextCode = Array(repeating: "", count: RDConfig.Auth.emailOTPLength)
        for (index, digit) in sanitized.enumerated() where index < nextCode.count {
            nextCode[index] = String(digit)
        }
        code = nextCode
        authError = nil

        if sanitized.count < RDConfig.Auth.emailOTPLength {
            autoVerifiedCode = nil
        } else if sanitized.count == RDConfig.Auth.emailOTPLength, autoVerifiedCode != sanitized, !isVerifyingEmailCode {
            autoVerifiedCode = sanitized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                verifyEmailCode()
            }
        }
    }

    private func otpDigitBox(index: Int) -> some View {
        let activeIndex = min(otpInput.count, RDConfig.Auth.emailOTPLength - 1)
        let isActive = focusedField == .otp && otpInput.count < RDConfig.Auth.emailOTPLength && index == activeIndex
        let hasValue = !code[index].isEmpty

        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isActive ? Color.rdGreen : (hasValue ? Color.rdOnyx.opacity(0.72) : Color.rdLine), lineWidth: isActive ? 2 : 1.5)
                )
                .shadow(color: isActive ? Color.rdGreen.opacity(0.18) : .clear, radius: 12, x: 0, y: 4)

            Text(code[index])
                .multilineTextAlignment(.center)
                .font(RDTypography.font(size: RDFontScale.size(28), weight: .bold, design: .monospaced))
                .foregroundStyle(Color.rdOnyx)

            if isActive && !hasValue {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.rdGreen)
                    .frame(width: 2, height: 28)
                    .opacity(caretPulse ? 1 : 0.22)
                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: caretPulse)
            }
        }
        .frame(width: 48, height: 58)
    }
}

private struct GoogleMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)

            Text(RDLocalization.string("auth.auth.view.g.1bdc8bd9", table: .auth, fallback: "G"))
                .font(RDTypography.font(size: RDFontScale.size(16), weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "#4285F4"),
                            Color(hex: "#34A853"),
                            Color(hex: "#FBBC05"),
                            Color(hex: "#EA4335")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            Circle()
                .stroke(Color.rdLine, lineWidth: 0.8)
        )
    }
}

private struct GoogleWordmark: View {
    static var localizedTitle: String {
        RDLocalization.string(
            "auth.google.continue",
            table: .auth,
            fallback: "Google ile devam et"
        )
    }

    var body: some View {
        localizedText
        .font(RDTypography.font(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
        .tracking(-0.2)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityHidden(true)
    }

    private var localizedText: Text {
        let title = Self.localizedTitle
        guard let range = title.range(of: "Google", options: [.caseInsensitive]) else {
            return Text(title).foregroundColor(Color.rdOnyx)
        }

        let prefix = String(title[..<range.lowerBound])
        let suffix = String(title[range.upperBound...])
        return Text(prefix).foregroundColor(Color.rdOnyx)
            + googleBrandText
            + Text(suffix).foregroundColor(Color.rdOnyx)
    }

    private var googleBrandText: Text {
        Text("G").foregroundColor(Color(hex: "#4285F4"))
            + Text("o").foregroundColor(Color(hex: "#EA4335"))
            + Text("o").foregroundColor(Color(hex: "#FBBC05"))
            + Text("g").foregroundColor(Color(hex: "#4285F4"))
            + Text("l").foregroundColor(Color(hex: "#34A853"))
            + Text("e").foregroundColor(Color(hex: "#EA4335"))
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
