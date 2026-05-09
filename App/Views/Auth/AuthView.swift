import SwiftUI

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var phase: AuthPhase = .options
    @State private var email: String = ""
    @State private var code: [String] = Array(repeating: "", count: 6)
    @State private var signingInDemo: DemoAccount?
    @State private var authError: String?
    @State private var showLegalInfo = false
    @State private var isSendingEmailCode = false
    @State private var isVerifyingEmailCode = false
    @State private var isSigningInWithApple = false
    @State private var isSigningInWithGoogle = false
    @State private var appleSignInService = AppleSignInService()

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
    private var otpCode: String { code.joined() }
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
                        .init(color: .clear,                           location: 0.22),
                        .init(color: Color.rdPaper.opacity(0.30),      location: 0.38),
                        .init(color: Color.rdPaper.opacity(0.78),      location: 0.52),
                        .init(color: Color.rdPaper.opacity(0.97),      location: 0.62),
                        .init(color: Color.rdPaper,                    location: 0.70),
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

                // MARK: Logo + subtitle — gradient'ın açık bölgesinde
                VStack(spacing: 10) {
                    RDLogo(size: 38)
                    Text("Saha için yapay zekâ destekli iş güvenliği asistanı")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                .padding(.bottom, formHeight + 32)
                .frame(maxWidth: .infinity)

                // MARK: Form — alttan sabit
                VStack(spacing: 0) {
                    form
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(28, geo.safeAreaInsets.bottom))
                        .padding(.top, 8)
                }
                .frame(height: formHeight)
                .background(Color.rdPaper)
            }
        }
        .ignoresSafeArea()
        .background(Color.rdPaper)
        .sheet(isPresented: $showLegalInfo) {
            LegalInfoSheet(onClose: { showLegalInfo = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // Form yüksekliği phase'e göre değişmez, badge pozisyonu için sabit referans
    private var formHeight: CGFloat {
        switch phase {
        case .options: return 326
        case .email:   return 220
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
                icon: isSigningInWithApple ? "hourglass" : "applelogo"
            ) {
                runAppleSignIn()
            }
            .disabled(isSigningInWithApple)
            .opacity(isSigningInWithApple ? 0.75 : 1)
            RDButton(
                title: isSigningInWithGoogle ? "Google ile bağlanıyor..." : "Google ile devam et",
                style: .secondary,
                icon: isSigningInWithGoogle ? "hourglass" : "g.circle.fill"
            ) {
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
            RDButton(title: "E-posta kodu ile devam et", style: .secondary, icon: "envelope.fill") {
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
                Text(err)
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

    private var legalNotice: some View {
        VStack(spacing: 3) {
            Text("Üye olarak veya giriş yaparak RiskDetected kullanım koşullarını kabul etmiş sayılırsın.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .multilineTextAlignment(.center)
                .lineLimit(2)

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
            Text(err)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdCritical)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
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
                TextField("mail@ornek.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, design: .rounded))
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
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(Color.rdSlate)
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
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    TextField("", text: Binding(
                        get: { code[i] },
                        set: { code[i] = String($0.filter(\.isNumber).prefix(1)) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .frame(width: 48, height: 58)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(code[i].isEmpty ? Color.rdLine : Color.rdBlack, lineWidth: 1.5)
                    )
                }
            }
            .frame(maxWidth: .infinity)

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
                authError = AppErrorMessage.make(error, context: "Giriş yapılamadı", fallbackTitle: "Giriş yapılamadı").fullText
            }
            signingInDemo = nil
        }
    }

    private func sendEmailCode() {
        guard canSendEmailCode else { return }
        isSendingEmailCode = true
        authError = nil
        Task {
            do {
                try await app.auth.sendEmailOTP(email: normalizedEmail)
                code = Array(repeating: "", count: 6)
                withAnimation(.easeInOut(duration: 0.22)) { phase = .otp }
            } catch {
                authError = AppErrorMessage.make(error, context: "Kod gönderilemedi", fallbackTitle: "Kod gönderilemedi").fullText
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
                authError = AppErrorMessage.make(error, context: "Kod doğrulanamadı", fallbackTitle: "Kod doğrulanamadı").fullText
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
                authError = AppErrorMessage.make(error, context: "Apple ile giriş yapılamadı", fallbackTitle: "Apple ile giriş yapılamadı").fullText
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
                authError = AppErrorMessage.make(error, context: "Google ile giriş yapılamadı", fallbackTitle: "Google ile giriş yapılamadı").fullText
            }
            isSigningInWithGoogle = false
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
