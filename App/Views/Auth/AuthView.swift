import SwiftUI

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var phase: AuthPhase = .options
    @State private var phone: String = ""
    @State private var code: [String] = ["", "", "", ""]
    @State private var signingInDemo: DemoAccount?
    @State private var authError: String?
    @State private var showLegalInfo = false

    enum AuthPhase { case options, phone, otp }
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
                        .font(.system(size: 13, weight: .medium))
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
        case .phone:   return 220
        case .otp:     return 280
        }
    }

    @ViewBuilder
    private var form: some View {
        switch phase {
        case .options: optionsForm
        case .phone:   phoneForm
        case .otp:     otpForm
        }
    }

    // MARK: - Options

    private var optionsForm: some View {
        VStack(spacing: 10) {
            RDButton(title: "Apple ile devam et", style: .primary, icon: "applelogo") {
                // TODO: ASAuthorizationAppleIDProvider
            }
            RDButton(title: "Google ile devam et", style: .secondary, icon: "g.circle.fill") {
                // TODO: GoogleSignIn SDK
            }
            HStack(spacing: 12) {
                Rectangle().fill(Color.rdLine).frame(height: 1)
                Text("veya").font(.system(size: 12)).foregroundStyle(Color.rdSlate)
                Rectangle().fill(Color.rdLine).frame(height: 1)
            }
            .padding(.vertical, 2)
            RDButton(title: "Telefon numarası ile", style: .secondary, icon: "phone.fill") {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .phone }
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            if let svcErr = app.authError {
                Text("⚠️ \(svcErr)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var legalNotice: some View {
        VStack(spacing: 3) {
            Text("Üye olarak veya giriş yaparak RiskDetected kullanım koşullarını kabul etmiş sayılırsın.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.rdSlate)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button {
                showLegalInfo = true
            } label: {
                Text("KVKK · Kullanım koşulları · AI veri işleme")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.rdGreenDark)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Phone

    private var phoneForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Telefon numarası")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.rdSlate)
            HStack(spacing: 8) {
                Text("🇹🇷 +90")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 84, height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                TextField("555 000 00 00", text: $phone)
                    .keyboardType(.phonePad)
                    .font(.system(size: 16))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
            }
            RDButton(title: "Kod gönder", style: .primary, trailingIcon: "arrow.right") {
                if phone.filter(\.isNumber).count >= 10 {
                    withAnimation(.easeInOut(duration: 0.22)) { phase = .otp }
                }
            }
            Button("← Diğer giriş yöntemleri") {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .options }
            }
            .font(.system(size: 14))
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.rdSlate)
                Text("+90 \(phone.isEmpty ? "555 000 00 00" : phone) numarasına gönderildi")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.rdInk)
            }
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    TextField("", text: Binding(
                        get: { code[i] },
                        set: { code[i] = String($0.filter(\.isNumber).prefix(1)) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .frame(width: 64, height: 64)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(code[i].isEmpty ? Color.rdLine : Color.rdBlack, lineWidth: 1.5)
                    )
                }
            }
            .frame(maxWidth: .infinity)

            Text("Kod gelmedi mi? **00:32** sonra tekrar gönder")
                .font(.system(size: 13))
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: .infinity)

            RDButton(title: "Doğrula ve giriş yap", style: .detect) {}

            Button("← Numarayı değiştir") {
                withAnimation(.easeInOut(duration: 0.22)) { phase = .phone }
            }
            .font(.system(size: 14))
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
                    .font(.system(size: 12, weight: .bold))
                Text(signingInDemo == account ? "Giriş..." : account.title)
                    .font(.system(size: 12, weight: .bold))
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
                authError = "Giriş başarısız: \(error.localizedDescription)"
            }
            signingInDemo = nil
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
