import SwiftUI

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var phase: AuthPhase = .options
    @State private var phone: String = ""
    @State private var code: [String] = ["", "", "", ""]
    @State private var heroVariant: HeroVariant = .photo
    @State private var isSigningIn: Bool = false
    @State private var authError: String?

    enum AuthPhase { case options, phone, otp }
    enum HeroVariant: String { case photo, mascot }

    var body: some View {
        ZStack(alignment: .top) {
            Color.rdPaper.ignoresSafeArea()

            VStack(spacing: 0) {
                AuthHero(variant: heroVariant)
                    .frame(height: 360)
                    .clipped()
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 8) {
                    RDLogo(size: 24)
                    Text("Saha için yapay zekâ destekli iş güvenliği asistanı")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(.top, -76)
                .zIndex(2)

                Spacer(minLength: 0)

                form
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }

            // Variant toggle (top-left)
            HStack(spacing: 0) {
                ForEach([HeroVariant.photo, HeroVariant.mascot], id: \.self) { v in
                    Text(v == .photo ? "Foto" : "Maskot")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.4)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(heroVariant == v ? Color.rdBlack : Color.clear)
                        .foregroundStyle(heroVariant == v ? .white : Color.rdCharcoal)
                        .clipShape(Capsule())
                        .onTapGesture { withAnimation(.easeInOut) { heroVariant = v } }
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.85))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.black.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .padding(.leading, 16)
            .padding(.top, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var form: some View {
        switch phase {
        case .options:
            optionsForm
        case .phone:
            phoneForm
        case .otp:
            otpForm
        }
    }

    // MARK: - Options

    private var optionsForm: some View {
        VStack(spacing: 10) {
            RDButton(title: "Apple ile devam et", style: .primary, icon: "applelogo") {
                // TODO: ASAuthorizationAppleIDProvider entegrasyonu
            }
            RDButton(title: "Google ile devam et", style: .secondary, icon: "g.circle.fill") {
                // TODO: GoogleSignIn SDK entegrasyonu
            }
            HStack(spacing: 12) {
                Rectangle().fill(Color.rdLine).frame(height: 1)
                Text("veya").font(.system(size: 12)).foregroundStyle(Color.rdSlate)
                Rectangle().fill(Color.rdLine).frame(height: 1)
            }
            .padding(.vertical, 6)
            RDButton(title: "Telefon numarası ile", style: .secondary, icon: "phone.fill") {
                withAnimation { phase = .phone }
            }

            #if DEBUG
            RDButton(
                title: isSigningIn ? "Giriş yapılıyor..." : "Demo hesap ile gir",
                style: .ghost,
                icon: "person.crop.circle.badge.checkmark"
            ) {
                runDemoSignIn()
            }
            .padding(.top, 6)
            .opacity(isSigningIn ? 0.6 : 1)
            #endif

            if let err = authError {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            if let svcErr = app.authError {
                Text("⚠️ \(svcErr)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rdCritical)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            Text("Devam ederek/Kaydolarak Kullanım Şartları ve Gizlilik Politikası'nı kabul etmiş olursun.")
                .font(.system(size: 12))
                .foregroundStyle(Color.rdSlate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 14)
        }
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
                    withAnimation { phase = .otp }
                }
            }
            Button("← Diğer giriş yöntemleri") { withAnimation { phase = .options } }
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

            RDButton(title: "Doğrula ve giriş yap", style: .detect) {
                // TODO: SMS provider konfig sonrası verifyPhoneOTP çağrısı
            }

            Button("← Numarayı değiştir") { withAnimation { phase = .phone } }
                .font(.system(size: 14))
                .foregroundStyle(Color.rdSlate)
                .frame(maxWidth: .infinity)
                .padding(8)
        }
    }

    // MARK: - Demo sign-in

    private func runDemoSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        authError = nil
        Task {
            do {
                try await app.auth.signInWithPassword(
                    email: "demo@riskdetected.app",
                    password: "demo123456"
                )
                // AppState session değişimini gözlemleyip flow=.main yapacak.
            } catch {
                authError = "Giriş başarısız: \(error.localizedDescription)"
            }
            isSigningIn = false
        }
    }
}

struct AuthHero: View {
    let variant: AuthView.HeroVariant

    var body: some View {
        ZStack {
            if variant == .photo {
                heroPhoto
            } else {
                heroMascot
            }

            // Top fade
            LinearGradient(
                colors: [Color.rdPaper, Color.rdPaper.opacity(0.85), Color.rdPaper.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 110)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            // Bottom fade
            LinearGradient(
                colors: [Color.rdPaper.opacity(0), Color.rdPaper.opacity(0.85), Color.rdPaper],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 160)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            // Floating "scan complete" badge
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.rdGreen).frame(width: 22, height: 22)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("SAHA TARAMASI")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Color.rdSlate)
                    Text("3 risk tespit edildi")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.95))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.04), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
            .padding(.trailing, 18).padding(.top, 78)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
        .frame(height: 360)
    }

    @ViewBuilder
    private var heroPhoto: some View {
        ZStack {
            // Sky gradient
            LinearGradient(
                colors: [Color(hex: "#A8C5DA"), Color(hex: "#E8EFF4")],
                startPoint: .top, endPoint: .bottom
            )

            // Construction silhouette
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.62))
                    p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.48))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.40))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.50))
                    p.addLine(to: CGPoint(x: w, y: h * 0.45))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [Color(hex: "#1F2D3D"), Color(hex: "#0B1218")],
                    startPoint: .top, endPoint: .bottom
                ))
            }
        }
    }

    @ViewBuilder
    private var heroMascot: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#EAF8EE"), Color.rdPaper],
                startPoint: .top, endPoint: .bottom
            )
            // Helmet mascot — basit SwiftUI çizimi
            ZStack {
                Capsule()
                    .fill(Color.rdGreen)
                    .frame(width: 180, height: 110)
                    .offset(y: 6)
                Capsule()
                    .fill(Color.rdGreenDark)
                    .frame(width: 200, height: 18)
                    .offset(y: 60)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: 4)
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
