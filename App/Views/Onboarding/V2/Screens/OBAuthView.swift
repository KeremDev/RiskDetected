import SwiftUI
import UIKit

struct OBAuthView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var state: OnboardingV2State
    @StateObject private var keyboard = OBKeyboardObserver()
    let onBack: () -> Void
    let onApple: () -> Void
    let onGoogle: () -> Void
    let onEmail: () -> Void
    let onSignIn: () -> Void
    @State private var emailPhase: EmailPhase = .hidden
    @State private var email = ""
    @State private var otpInput = ""
    @State private var autoVerifiedCode: String?
    @State private var code = Array(repeating: "", count: 6)
    @State private var isSendingEmailCode = false
    @State private var isVerifyingEmailCode = false
    @State private var authErrorMessage: String?
    @State private var focusRequest = 0

    private enum EmailPhase {
        case hidden
        case email
        case otp
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSendEmailCode: Bool {
        normalizedEmail.contains("@") && normalizedEmail.contains(".") && !isSendingEmailCode
    }

    private var canVerifyEmailCode: Bool {
        otpInput.count == 6 && !isVerifyingEmailCode
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent

            if emailPhase != .hidden {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        if emailPhase == .email {
                            focusEmailField()
                        } else {
                            focusOTPField()
                        }
                    }

                emailAuthPanel
                    .padding(.horizontal, 20)
                    .padding(.bottom, keyboard.visibleHeight > 0 ? keyboard.visibleHeight + 10 : 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .background(Color.rdPaper)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.obSpring, value: emailPhase)
        .animation(.easeOut(duration: keyboard.animationDuration), value: keyboard.visibleHeight)
        .accessibilityIdentifier("onboarding.auth")
        .onChange(of: emailPhase) { newPhase in
            if newPhase == .email {
                focusEmailField()
            } else if newPhase == .otp {
                focusOTPField()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button { OBHaptic.soft(); onBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.rdOnyx)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: 0) {
                    OBHeroTile(tint: .green) { OBHeroAuth() }
                        .padding(.top, 16)
                        .obStage(delay: 0.04)

                    Text("Son adım.")
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Color.rdOnyx)
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)
                        .obStage(delay: 0.08)

                    Text("Hazırladığın planı kaydedebilmen için hesabını oluşturalım.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 310)
                        .padding(.top, 10)
                        .obStage(delay: 0.16)

                    planRecap
                        .padding(.top, 24)
                        .obStage(delay: 0.24)

                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(height: 1)
                        .padding(.top, 24)
                        .obStage(delay: 0.3)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.rdGreenDark)
                        Text("Planın hesabına kilitlensin diye 10 saniyeni alacağız")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.rdGreenSoft.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.rdGreen.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.top, 16)
                    .obStage(delay: 0.32)

                    VStack(spacing: 10) {
                        authButton(
                            title: "Apple ile devam et",
                            icon: { Image(systemName: "apple.logo").font(.system(size: 18, weight: .medium)) },
                            bg: .black, fg: .white, bordered: false
                        ) { OBHaptic.light(); onApple() }
                        .accessibilityIdentifier("onboarding.auth.apple")
                        .obStage(delay: 0.36)

                        Button {
                            OBHaptic.light(); onGoogle()
                        } label: {
                            HStack(spacing: 10) {
                                googleG
                                googleTextColored
                            }
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
                        }
                        .buttonStyle(OBPressStyle())
                        .accessibilityIdentifier("onboarding.auth.google")
                        .obStage(delay: 0.44)

                        if emailPhase == .hidden {
                            Button {
                                OBHaptic.light()
                                onEmail()
                                withAnimation(.obSpring) { emailPhase = .email }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "envelope").font(.system(size: 16))
                                    Text("E-posta ile devam et").font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundStyle(Color.rdOnyx)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(Color.rdFog)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.rdLine, lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                            }
                            .buttonStyle(OBPressStyle())
                            .accessibilityIdentifier("onboarding.auth.email")
                            .obStage(delay: 0.52)
                        } else {
                            activeEmailRow
                                .obStage(delay: 0.52)
                        }
                    }
                    .padding(.top, 14)

                    Button {
                        OBHaptic.light()
                        onSignIn()
                        withAnimation(.obSpring) { emailPhase = .email }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.rdSlate)
                            Text("Zaten hesabım var · ")
                                .font(.system(size: 13))
                                .foregroundColor(Color.rdSlate)
                            + Text("Giriş Yap")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.rdOnyx)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.rdFog.opacity(0.6))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.rdLine, lineWidth: 1))
                    }
                    .buttonStyle(OBPressStyle())
                    .accessibilityIdentifier("onboarding.auth.sign_in_existing")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .obStage(delay: 0.62)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.never)

            finePrint
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .obStage(delay: 0.7)
        }
    }

    private var activeEmailRow: some View {
        Button {
            OBHaptic.light()
            if emailPhase == .otp {
                focusOTPField()
            } else {
                focusEmailField()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: emailPhase == .otp ? "number.square.fill" : "envelope.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(emailPhase == .otp ? "Kod doğrulama açık" : "E-posta ile devam")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdOnyx)
                    Text(emailPhase == .otp ? normalizedEmail : "E-posta adresini gir")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.rdSlate)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.rdLine, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(OBPressStyle())
    }

    private var emailAuthPanel: some View {
        VStack(alignment: .leading, spacing: emailPhase == .otp ? 11 : 13) {
            panelHeader

            if emailPhase == .email {
                emailInputRow

                Button {
                    sendEmailCode()
                } label: {
                    HStack(spacing: 8) {
                        Text(isSendingEmailCode ? "Kod gönderiliyor..." : "Kod gönder")
                        Image(systemName: isSendingEmailCode ? "hourglass" : "arrow.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.rdOnyx.opacity(canSendEmailCode ? 1 : 0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(OBPressStyle())
                .disabled(!canSendEmailCode)
                .accessibilityIdentifier("onboarding.auth.email.send_code")
            } else {
                otpInputRow

                Button {
                    verifyEmailCode()
                } label: {
                    HStack(spacing: 8) {
                        Text(isVerifyingEmailCode ? "Doğrulanıyor..." : "Doğrula ve devam et")
                        Image(systemName: isVerifyingEmailCode ? "hourglass" : "arrow.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.rdGreen.opacity(canVerifyEmailCode ? 1 : 0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(OBPressStyle())
                .disabled(!canVerifyEmailCode)
                .accessibilityIdentifier("onboarding.auth.email.verify_code")

                HStack {
                    Button("Yeni kod gönder") {
                        resendEmailCode()
                    }
                    .disabled(isSendingEmailCode)
                    Spacer()
                    Button("E-postayı değiştir") {
                        withAnimation(.obSpring) { emailPhase = .email }
                        otpInput = ""
                        autoVerifiedCode = nil
                        authErrorMessage = nil
                        focusEmailField()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.rdSlate)
            }

            if let authErrorMessage {
                Text(authErrorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(emailPhase == .otp ? 14 : 16)
        .background(
            LinearGradient(
                colors: [Color.white, Color.rdPaper.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.9), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.rdLine.opacity(0.78), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
        .accessibilityIdentifier(emailPhase == .otp ? "onboarding.auth.otp_panel" : "onboarding.auth.email_panel")
    }

    private var panelHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: emailPhase == .otp ? "number.square.fill" : "envelope.fill")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 36, height: 36)
                .background(Color.rdGreen.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(emailPhase == .otp ? "Doğrulama kodu" : "E-posta adresinizi giriniz")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdOnyx)
                Text(emailPhase == .otp ? "\(normalizedEmail) adresine gönderildi" : "Kod göndermek için e-posta adresini yaz.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                OBHaptic.light()
                withAnimation(.obSpring) {
                    emailPhase = emailPhase == .otp ? .email : .hidden
                }
                authErrorMessage = nil
                if emailPhase == .email {
                    focusEmailField()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 32, height: 32)
                    .background(Color.rdPaper)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emailInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdOnyx.opacity(0.82))
                .frame(width: 54, height: 54)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.rdLine, lineWidth: 1))

            OBFirstResponderTextField(
                text: $email,
                placeholder: "Mailinizi yazınız...",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                isFirstResponder: emailPhase == .email,
                focusRequest: focusRequest,
                maxLength: nil,
                onChange: { _ in authErrorMessage = nil },
                onSubmit: {
                    if canSendEmailCode {
                        sendEmailCode()
                    }
                }
            )
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.rdLine, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusEmailField()
        }
        .onAppear {
            focusEmailField()
        }
    }

    private var otpInputRow: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { index in
                    otpDigitBox(index: index)
                }
            }
            .allowsHitTesting(false)

            OBFirstResponderTextField(
                text: $otpInput,
                placeholder: "",
                keyboardType: .numberPad,
                textContentType: .oneTimeCode,
                isFirstResponder: emailPhase == .otp,
                focusRequest: focusRequest,
                maxLength: 6,
                onChange: { value in
                    syncOTPInput(value)
                },
                onSubmit: {}
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityLabel("Doğrulama kodu")
            .accessibilityIdentifier("onboarding.auth.otp_input")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .contentShape(Rectangle())
        .onTapGesture {
            focusOTPField()
        }
        .onAppear {
            focusOTPField()
        }
    }

    private func sendEmailCode() {
        guard canSendEmailCode else { return }
        isSendingEmailCode = true
        authErrorMessage = nil
        Task {
            do {
                try await app.auth.sendEmailOTP(email: normalizedEmail)
                autoVerifiedCode = nil
                otpInput = ""
                code = Array(repeating: "", count: 6)
                withAnimation(.obSpring) { emailPhase = .otp }
                focusOTPField()
            } catch {
                setAuthError(error, context: "Kod gönderilemedi", fallbackTitle: "Kod gönderilemedi", operation: "onboarding_send_email_otp")
            }
            isSendingEmailCode = false
        }
    }

    private func resendEmailCode() {
        guard !isSendingEmailCode else { return }
        sendEmailCode()
    }

    private func verifyEmailCode() {
        guard canVerifyEmailCode else { return }
        isVerifyingEmailCode = true
        authErrorMessage = nil
        Task {
            do {
                try await app.auth.verifyEmailOTP(email: normalizedEmail, token: otpInput)
                await app.auth.refreshProfile()
            } catch {
                setAuthError(error, context: "Kod doğrulanamadı", fallbackTitle: "Kod doğrulanamadı", operation: "onboarding_verify_email_otp")
            }
            isVerifyingEmailCode = false
        }
    }

    private func setAuthError(_ error: Error, context: String, fallbackTitle: String, operation: String) {
        let message = AppErrorMessage.make(
            error,
            context: context,
            fallbackTitle: fallbackTitle
        )
        AuthService.logAuthError(message, operation: operation, email: normalizedEmail)
        authErrorMessage = message.message
    }

    private func focusEmailField() {
        DispatchQueue.main.async {
            guard emailPhase == .email else { return }
            focusRequest += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard emailPhase == .email else { return }
            focusRequest += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            guard emailPhase == .email else { return }
            focusRequest += 1
        }
    }

    private func focusOTPField() {
        DispatchQueue.main.async {
            guard emailPhase == .otp else { return }
            focusRequest += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard emailPhase == .otp else { return }
            focusRequest += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            guard emailPhase == .otp else { return }
            focusRequest += 1
        }
    }

    private func syncOTPInput(_ value: String) {
        let sanitized = String(value.filter(\.isNumber).prefix(6))
        if sanitized != otpInput {
            otpInput = sanitized
            return
        }

        var nextCode = Array(repeating: "", count: 6)
        for (index, digit) in sanitized.enumerated() where index < nextCode.count {
            nextCode[index] = String(digit)
        }
        code = nextCode
        authErrorMessage = nil

        if sanitized.count < 6 {
            autoVerifiedCode = nil
        } else if sanitized.count == 6, autoVerifiedCode != sanitized, !isVerifyingEmailCode {
            autoVerifiedCode = sanitized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard otpInput == sanitized else { return }
                verifyEmailCode()
            }
        }
    }

    private func otpDigitBox(index: Int) -> some View {
        let activeIndex = min(otpInput.count, 5)
        let isActive = emailPhase == .otp && otpInput.count < 6 && index == activeIndex
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
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.rdOnyx)

            if isActive && !hasValue {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.rdGreen)
                    .frame(width: 2, height: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
    }

    private var planRecap: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.rdGreen)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                    Text("SANA ÖZEL")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                }
                .foregroundStyle(Color.rdGreenDark)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.rdGreenSoft)
                .overlay(Capsule().stroke(Color.rdGreen.opacity(0.22), lineWidth: 1))
                .clipShape(Capsule())

                Text("Planın hazır, seni bekliyor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.rdOnyx)
                Text("47 şablon · \(state.primarySectorLabel) · \(state.certificateLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdOnyx.opacity(0.06), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            OBPulseDot().padding(10)
        }
    }

    private var finePrint: some View {
        Text(makeFinePrint())
            .font(.system(size: 12))
            .foregroundStyle(Color.rdSlate.opacity(0.85))
            .lineSpacing(3)
    }

    private func makeFinePrint() -> AttributedString {
        var s = AttributedString("Devam ederek ")
        var a = AttributedString("Kullanım Şartları'nı")
        a.foregroundColor = Color.rdGraphite
        a.underlineStyle = .single
        s.append(a)
        s.append(AttributedString(" ve "))
        var b = AttributedString("Gizlilik Politikası'nı")
        b.foregroundColor = Color.rdGraphite
        b.underlineStyle = .single
        s.append(b)
        s.append(AttributedString(" kabul etmiş olursun."))
        return s
    }

    private func authButton<Icon: View>(
        title: String,
        @ViewBuilder icon: () -> Icon,
        bg: Color, fg: Color, bordered: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.rdLine, lineWidth: bordered ? 1 : 0)
            )
            .shadow(color: .black.opacity(bordered ? 0.05 : 0), radius: 8, y: 3)
        }
        .buttonStyle(OBPressStyle())
    }

    private var googleG: some View {
        GoogleGLogo()
            .frame(width: 20, height: 20)
    }

    private var googleTextColored: some View {
        // "Google" with Google brand colors per letter
        HStack(spacing: 0) {
            Text("G").foregroundStyle(Color(hex: "#4285F4"))
            Text("o").foregroundStyle(Color(hex: "#EA4335"))
            Text("o").foregroundStyle(Color(hex: "#FBBC05"))
            Text("g").foregroundStyle(Color(hex: "#4285F4"))
            Text("l").foregroundStyle(Color(hex: "#34A853"))
            Text("e").foregroundStyle(Color(hex: "#EA4335"))
            Text(" ile devam et").foregroundStyle(Color.rdOnyx)
        }
        .font(.system(size: 16, weight: .semibold))
    }
}

// MARK: - Pulse dot (planın yaşıyor hissi)

private struct OBPulseDot: View {
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0.6

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.rdGreen.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(scale)
                .opacity(opacity)
            Circle()
                .fill(Color.rdGreen)
                .frame(width: 8, height: 8)
                .shadow(color: Color.rdGreen.opacity(0.5), radius: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                scale = 1.8
                opacity = 0
            }
        }
    }
}

// MARK: - Google "G" logo (proper 4-color shape)

private struct GoogleGLogo: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2
            let cy = size.height / 2
            let r = s * 0.46
            let inner = s * 0.20

            let blue = Color(hex: "#4285F4")
            let red = Color(hex: "#EA4335")
            let yellow = Color(hex: "#FBBC05")
            let green = Color(hex: "#34A853")

            func segment(start: CGFloat, end: CGFloat, color: Color) {
                var p = Path()
                p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(Double(start)),
                         endAngle: .degrees(Double(end)),
                         clockwise: false)
                p.addLine(to: CGPoint(
                    x: cx + cos(end * .pi / 180) * inner,
                    y: cy + sin(end * .pi / 180) * inner
                ))
                p.addArc(center: CGPoint(x: cx, y: cy), radius: inner,
                         startAngle: .degrees(Double(end)),
                         endAngle: .degrees(Double(start)),
                         clockwise: true)
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
            }

            segment(start: -90, end: 0, color: red)
            segment(start: 0, end: 80, color: yellow)
            segment(start: 80, end: 200, color: green)
            segment(start: 200, end: 270, color: blue)

            // Horizontal bar (mouth of G) — small blue rect right side
            let barRect = CGRect(x: cx + inner * 0.4, y: cy - s * 0.05,
                                 width: r - inner * 0.4 + 0.5, height: s * 0.10)
            ctx.fill(Path(barRect), with: .color(blue))
        }
    }
}

private struct OBFirstResponderTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let isFirstResponder: Bool
    let focusRequest: Int
    let maxLength: Int?
    let onChange: (String) -> Void
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.returnKeyType = .continue
        textField.clearButtonMode = .never
        textField.font = .rdRounded(ofSize: 17, weight: .medium)
        textField.textColor = UIColor(Color.rdOnyx)
        textField.tintColor = UIColor(Color.rdGreen)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor(Color.rdOnyx.opacity(0.34)),
                .font: UIFont.rdRounded(ofSize: 17, weight: .medium)
            ]
        )
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }

        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor(Color.rdOnyx.opacity(0.34)),
                .font: UIFont.rdRounded(ofSize: 17, weight: .medium)
            ]
        )

        if isFirstResponder {
            if !textField.isFirstResponder || context.coordinator.lastFocusRequest != focusRequest {
                context.coordinator.lastFocusRequest = focusRequest
                Self.focus(textField, attempt: 0)
            }
        } else if textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private static func focus(_ textField: UITextField, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) {
            guard textField.window != nil else {
                if attempt < 24 {
                    focus(textField, attempt: attempt + 1)
                }
                return
            }

            if !textField.isFirstResponder {
                textField.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OBFirstResponderTextField
        var lastFocusRequest = -1

        init(parent: OBFirstResponderTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            var value = textField.text ?? ""

            if parent.keyboardType == .numberPad {
                value = value.filter(\.isNumber)
            }

            if let maxLength = parent.maxLength {
                value = String(value.prefix(maxLength))
            }

            if textField.text != value {
                textField.text = value
            }

            parent.text = value
            parent.onChange(value)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

private extension UIFont {
    static func rdRounded(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

@MainActor
private final class OBKeyboardObserver: ObservableObject {
    @Published var visibleHeight: CGFloat = 0
    @Published var animationDuration: Double = 0.25

    private var showObserver: NSObjectProtocol?
    private var hideObserver: NSObjectProtocol?

    init() {
        showObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleKeyboard(notification)
            }
        }

        hideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.animationDuration = Self.duration(from: notification)
                self?.visibleHeight = 0
            }
        }
    }

    deinit {
        if let showObserver {
            NotificationCenter.default.removeObserver(showObserver)
        }
        if let hideObserver {
            NotificationCenter.default.removeObserver(hideObserver)
        }
    }

    private func handleKeyboard(_ notification: Notification) {
        animationDuration = Self.duration(from: notification)
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
        else {
            visibleHeight = 0
            return
        }

        let keyboardOverlap = max(0, window.bounds.maxY - frame.minY)
        let safeBottom = window.safeAreaInsets.bottom
        visibleHeight = max(0, keyboardOverlap - safeBottom)
    }

    private static func duration(from notification: Notification) -> Double {
        notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    }
}
