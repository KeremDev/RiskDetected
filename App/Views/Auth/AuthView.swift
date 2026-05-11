import SwiftUI

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var phase: AuthPhase = .options
    @State private var email: String = ""
    @State private var code: [String] = Array(repeating: "", count: 6)
    @State private var otpInput: String = ""
    @State private var signingInDemo: DemoAccount?
    @State private var authError: AppErrorMessage?
    @State private var showLegalInfo = false
    @State private var isSendingEmailCode = false
    @State private var isVerifyingEmailCode = false
    @State private var isSigningInWithApple = false
    @State private var isSigningInWithGoogle = false
    @State private var appleSignInService = AppleSignInService()
    @State private var autoVerifiedCode: String?
    @State private var caretPulse = false
    @FocusState private var isOTPInputFocused: Bool

    enum AuthPhase { case options, email, otp }
    enum DemoAccount: String {
        case pro, free

        var title: String {
            switch self {
            case .pro: return "Pro demo"
            case .free: return "Free demo"
            }
        }

        var email: String {
            switch self {
            case .pro: return "demo@riskdetected.app"
            case .free: return "free@riskdetected.app"
            }
        }

        var password: String {
            switch self {
            case .pro: return "demo123456"
            case .free: return "free123456"
            }
        }

        var icon: String {
            switch self {
            case .pro: return "star.fill"
            case .free: return "person.crop.circle"
            }
        }

        var tint: Color {
            switch self {
            case .pro: return Color.rdGreen
            case .free: return Color.rdBlack
            }
        }
    }

    private var isSigningIn: Bool { signingInDemo != nil }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var otpCode: String { otpInput }
    private var canSendEmailCode: Bool { normalizedEmail.contains("@") && normalizedEmail.contains(".") && !isSendingEmailCode }
    private var canVerifyEmailCode: Bool { otpCode.count == 6 && !isVerifyingEmailCode }

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
                        .init(color: .clear,                           location: 0.18),
                        .init(color: Color.rdPaper.opacity(0.14),      location: 0.30),
                        .init(color: Color.rdPaper.opacity(0.42),      location: 0.43),
                        .init(color: Color.rdPaper.opacity(0.72),      location: 0.56),
                        .init(color: Color.rdPaper.opacity(0.94),      location: 0.70),
                        .init(color: Color.rdPaper,                    location: 0.84),
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
                VStack(spacing: phase == .email ? 18 : 20) {
                    VStack(spacing: 10) {
                        RDLogo(size: phase == .email ? 36 : 38)
                        Text("Saha için yapay zekâ destekli iş güvenliği asistanı")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 270)
                    }

                    form
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(18, geo.safeAreaInsets.bottom))
                }
                .padding(.bottom, max(22, geo.safeAreaInsets.bottom + 8))
                .offset(y: phase == .email ? -24 : 0)
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .background(Color.rdPaper)
        .sheet(isPresented: $showLegalInfo) {
            LegalInfoSheet(onClose: { showLegalInfo = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .otp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isOTPInputFocused = true
                }
                caretPulse = true
            } else {
                isOTPInputFocused = false
                caretPulse = false
            }
        }
        .onChange(of: isOTPInputFocused) { isFocused in
            caretPulse = isFocused
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
            RDButton(
                title: isSigningInWithApple ? "Apple ile bağlanıyor..." : "Apple ile devam et",
                style: .primary,
                icon: isSigningInWithApple ? "hourglass" : "applelogo",
                showsActionIcon: false
            ) {
                runAppleSignIn()
            }
            .disabled(isSigningInWithApple)
            .opacity(isSigningInWithApple ? 0.75 : 1)
            googleButton {
                runGoogleSignIn()
            }
            .disabled(isSigningInWithGoogle)
            .opacity(isSigningInWithGoogle ? 0.75 : 1)
            HStack(spacing: 12) {
                Rectangle().fill(Color.rdLine).frame(height: 1)
                Text("veya").font(.system(size: 12, design: .rounded)).foregroundStyle(Color.rdSlate)
                Rectangle().fill(Color.rdLine).frame(height: 1)
            }
            .padding(.vertical, 2)
            RDButton(title: "E-posta ile giriş yap", style: .secondary, icon: "envelope.fill") {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .email }
            }

            legalNotice

            #if DEBUG
            HStack(spacing: 8) {
                demoButton(.pro)
                demoButton(.free)
            }
            .opacity(isSigningIn ? 0.6 : 1)
            #endif

            if let err = authError {
                Text(err.message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            if let svcErr = app.authError {
                Text("⚠️ \(svcErr)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func googleButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isSigningInWithGoogle {
                    Image(systemName: "hourglass")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                } else {
                    GoogleMark()
                        .frame(width: 22, height: 22)
                }

                if isSigningInWithGoogle {
                    Text("Google ile bağlanıyor...")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
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
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var legalNotice: some View {
        VStack(spacing: 3) {
            Text("Üye olarak veya giriş yaparak\nRiskDetected koşullarını kabul etmiş sayılırsın.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Button {
                showLegalInfo = true
            } label: {
                Text("KVKK · Kullanım koşulları · AI veri işleme")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var authErrorText: some View {
        if let err = authError {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdCritical)
                        .padding(.top, 1)

                    Text(err.message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
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
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            Text(isSendingEmailCode ? "Yeni kod gönderiliyor..." : "Yeni kod gönder")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
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
            Text("E-posta adresi")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 54, height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                TextField(
                    "",
                    text: $email,
                    prompt: Text("Mailinizi yazınız  mail@ornek.com")
                        .foregroundColor(Color.rdSlate.opacity(0.48))
                )
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .tint(Color.rdGreen)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
            }
            RDButton(
                title: isSendingEmailCode ? "Kod gönderiliyor..." : "Kod gönder",
                style: .primary,
                trailingIcon: isSendingEmailCode ? "hourglass" : "arrow.right"
            ) {
                sendEmailCode()
            }
            .opacity(canSendEmailCode ? 1 : 0.55)
            .disabled(!canSendEmailCode)
            authErrorText
            Button("← Diğer giriş yöntemleri") {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .options }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.rdInk)
            .frame(maxWidth: .infinity)
            .padding(8)
        }
    }

    // MARK: - OTP

    private var otpForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Doğrulama kodu")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                Text("\(normalizedEmail.isEmpty ? "mail@ornek.com" : normalizedEmail) adresine gönderildi")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.rdInk)
            }
            ZStack {
                TextField("", text: $otpInput)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isOTPInputFocused)
                    .font(.system(size: 1))
                    .foregroundStyle(Color.clear)
                    .tint(Color.clear)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .opacity(0.01)
                    .onChange(of: otpInput) { newValue in
                        syncOTPInput(newValue)
                    }

                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        otpDigitBox(index: i)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                isOTPInputFocused = true
            }

            Text("Kod gelmedi mi? E-posta adresini kontrol edip tekrar gönderebilirsin.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: .infinity)

            RDButton(
                title: isVerifyingEmailCode ? "Doğrulanıyor..." : "Doğrula ve giriş yap",
                style: .detect,
                icon: isVerifyingEmailCode ? "hourglass" : nil
            ) {
                verifyEmailCode()
            }
            .opacity(canVerifyEmailCode ? 1 : 0.55)
            .disabled(!canVerifyEmailCode)
            authErrorText

            Button("← E-posta adresini değiştir") {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .email }
            }
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(Color.rdSlate)
            .frame(maxWidth: .infinity)
            .padding(8)
        }
    }

    // MARK: - Demo sign-in

    private func demoButton(_ account: DemoAccount) -> some View {
        Button {
            runDemoSignIn(account)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: signingInDemo == account ? "hourglass" : account.icon)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(signingInDemo == account ? "Giriş..." : account.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundStyle(account.tint)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(account.tint.opacity(account == .pro ? 0.45 : 0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(isSigningIn)
    }

    private func runDemoSignIn(_ account: DemoAccount) {
        guard !isSigningIn else { return }
        signingInDemo = account
        authError = nil
        Task {
            do {
                try await app.auth.signInWithPassword(
                    email: account.email,
                    password: account.password
                )
            } catch {
                setAuthError(error, context: "Giriş yapılamadı", fallbackTitle: "Giriş yapılamadı", operation: "demo_sign_in", email: account.email)
            }
            signingInDemo = nil
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
                code = Array(repeating: "", count: 6)
                if transitionToOTP {
                    withAnimation(.easeInOut(duration: 0.22)) { phase = .otp }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    isOTPInputFocused = true
                }
            } catch {
                setAuthError(error, context: "Kod gönderilemedi", fallbackTitle: "Kod gönderilemedi", operation: "send_email_otp", email: normalizedEmail)
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
                setAuthError(error, context: "Kod doğrulanamadı", fallbackTitle: "Kod doğrulanamadı", operation: "verify_email_otp", email: normalizedEmail)
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
                try await app.auth.signInWithApple(idToken: result.idToken, nonce: result.nonce)
                await app.auth.refreshProfile()
            } catch {
                setAuthError(error, context: "Apple ile giriş yapılamadı", fallbackTitle: "Apple ile giriş yapılamadı", operation: "apple_sign_in")
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
                try await app.auth.signInWithGoogleOAuth()
            } catch {
                setAuthError(error, context: "Google ile giriş yapılamadı", fallbackTitle: "Google ile giriş yapılamadı", operation: "google_sign_in")
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

    private func syncOTPInput(_ newValue: String) {
        let sanitized = String(newValue.filter(\.isNumber).prefix(6))
        if sanitized != otpInput {
            otpInput = sanitized
            return
        }

        var nextCode = Array(repeating: "", count: 6)
        for (index, digit) in sanitized.enumerated() where index < nextCode.count {
            nextCode[index] = String(digit)
        }
        code = nextCode
        authError = nil

        if sanitized.count < 6 {
            autoVerifiedCode = nil
        } else if sanitized.count == 6, autoVerifiedCode != sanitized, !isVerifyingEmailCode {
            autoVerifiedCode = sanitized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                verifyEmailCode()
            }
        }
    }

    private func otpDigitBox(index: Int) -> some View {
        let activeIndex = min(otpInput.count, 5)
        let isActive = isOTPInputFocused && otpInput.count < 6 && index == activeIndex
        let hasValue = !code[index].isEmpty

        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isActive ? Color.rdGreen : (hasValue ? Color.rdBlack : Color.rdLine), lineWidth: isActive ? 2 : 1.5)
                )
                .shadow(color: isActive ? Color.rdGreen.opacity(0.18) : .clear, radius: 12, x: 0, y: 4)

            Text(code[index])
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.rdBlack)

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

            Text("G")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
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
    var body: some View {
        HStack(spacing: 0) {
            Text("G").foregroundStyle(Color(hex: "#4285F4"))
            Text("o").foregroundStyle(Color(hex: "#EA4335"))
            Text("o").foregroundStyle(Color(hex: "#FBBC05"))
            Text("g").foregroundStyle(Color(hex: "#4285F4"))
            Text("l").foregroundStyle(Color(hex: "#34A853"))
            Text("e").foregroundStyle(Color(hex: "#EA4335"))
            Text(" ile devam et").foregroundStyle(Color.rdBlack)
        }
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .tracking(-0.2)
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
