#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

// MARK: - Shared auth chrome

/// Apple / Google buttons, identical on the signup and login surfaces.
struct NovaOBProviderButtons: View {
    var appleTitle = "Apple ile devam et"
    var googleTitle = "Google ile devam et"
    let onApple: () -> Void
    let onGoogle: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onApple) {
                HStack(spacing: 9) {
                    NovaOBIconPath(path: NovaOBBrandIcon.apple, size: 19, color: .white, lineWidth: 0, filled: true)
                        .frame(width: 19, height: 22)
                        .offset(y: -2)
                    Text(appleTitle).font(NovaOB.font(17, 500)).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(NovaOB.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onGoogle) {
                HStack(spacing: 9) {
                    NovaOBGoogleMark().frame(width: 19, height: 19)
                    Text(googleTitle).font(NovaOB.font(17, 500)).foregroundColor(NovaOB.ink)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(hex: 0xDADCE0), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

enum NovaOBBrandIcon {
    static let apple = "M17.05 12.04c-.03-2.6 2.12-3.85 2.22-3.91-1.21-1.77-3.09-2.01-3.76-2.04-1.6-.13-3.12.93-3.93.93-.81 0-2.06-.91-3.39-.88-1.74.03-3.35 1.01-4.25 2.57-1.81 3.15-.46 7.81 1.3 10.37.86 1.25 1.89 2.65 3.24 2.6 1.3-.05 1.79-.84 3.36-.84 1.57 0 2.01.84 3.38.82 1.39-.02 2.27-1.27 3.12-2.53.98-1.45 1.38-2.85 1.4-2.92-.03-.01-2.69-1.03-2.72-4.09zM14.7 4.2c.71-.86 1.19-2.06 1.06-3.25-1.05.04-2.32.7-3.06 1.56-.66.76-1.24 1.98-1.09 3.15 1.17.09 2.38-.6 3.09-1.46z"
    static let mail = "M3 7.5l9 6 9-6"
    static let mailBox = "M2.5 4.5h19v15h-19z"
    static let lockBody = "M4 10.5h16v10.5H4z"
}

/// The four-colour Google glyph, drawn as its official quadrant paths.
struct NovaOBGoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            let parts: [(String, Color)] = [
                ("M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.44c-.28 1.5-1.13 2.77-2.4 3.62v3.01h3.88c2.27-2.09 3.6-5.17 3.6-8.82z", Color(hex: 0x4285F4)),
                ("M12 24c3.24 0 5.96-1.08 7.95-2.91l-3.88-3.01c-1.08.72-2.45 1.15-4.07 1.15-3.13 0-5.78-2.11-6.72-4.96H1.29v3.12C3.26 21.3 7.31 24 12 24z", Color(hex: 0x34A853)),
                ("M5.28 14.27A7.2 7.2 0 014.9 12c0-.79.14-1.56.38-2.27V6.61H1.29A11.98 11.98 0 000 12c0 1.94.46 3.77 1.29 5.39l3.99-3.12z", Color(hex: 0xFBBC05)),
                ("M12 4.75c1.77 0 3.35.61 4.6 1.8l3.44-3.44C17.95 1.19 15.24 0 12 0 7.31 0 3.26 2.7 1.29 6.61l3.99 3.12C6.22 6.88 8.87 4.75 12 4.75z", Color(hex: 0xEA4335))
            ]
            for (path, color) in parts {
                context.fill(NovaOBSVGParser.path(path, scale: scale), with: .color(color))
            }
        }
    }
}

/// Padlock with the shackle that lifts on a loop (`isgLock`).
struct NovaOBAnimatedLock: View {
    var tint: Color = .white
    var bodyColor: Color = .white
    var keyholeColor: Color = NovaOB.ink
    var size: CGFloat = 21

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.2) / 2.2
            ZStack {
                NovaOBIconPath(path: "M8.1 11.4V8.5a3.9 3.9 0 017.8 0v2.9", size: size, color: tint, lineWidth: 2)
                    .rotationEffect(.degrees(shackleAngle(phase)), anchor: .bottomTrailing)
                    .offset(y: shackleLift(phase))
                RoundedRectangle(cornerRadius: 2.6 * size / 24, style: .continuous)
                    .fill(bodyColor)
                    .frame(width: 14.8 * size / 24, height: 9.6 * size / 24)
                    .offset(y: (16 - 12) * size / 24)
                Circle()
                    .fill(keyholeColor)
                    .frame(width: 3 * size / 24, height: 3 * size / 24)
                    .offset(y: (16 - 12) * size / 24)
            }
            .frame(width: size, height: size)
        }
    }

    private func shackleAngle(_ phase: Double) -> Double {
        switch phase {
        case ..<0.26: return 0
        case ..<0.46: return -30 * ((phase - 0.26) / 0.2)
        case ..<0.74: return -30
        case ..<0.94: return -30 * (1 - (phase - 0.74) / 0.2)
        default: return 0
        }
    }

    private func shackleLift(_ phase: Double) -> CGFloat {
        (0.26...0.94).contains(phase) ? -2 : 0
    }
}

// MARK: - Hesap oluştur

struct NovaOBSignupScreen: View {
    @ObservedObject var controller: NovaOBController
    let onLogin: () -> Void

    private var lockLine: String {
        let name = controller.answers.name.novaTrimmed
        return name.isEmpty ? "Yanıtların güvende." : "\(name), yanıtların güvende."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    NovaOBBackButton { controller.toCard() }.padding(.leading, -12)
                    Spacer(minLength: 0)
                }

                Image("NovaOBSignupArt")
                    .resizable().scaledToFit()
                    .frame(width: 148, height: 148)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -6)
                    .padding(.bottom, -10)

                Text("Şimdi hesabına bağlayalım.")
                    .font(NovaOB.font(27, 700))
                    .tracking(-0.3)
                    .lineSpacing(NovaOB.lineSpacing(27, 1.2))
                    .fixedSize(horizontal: false, vertical: true)

                lockCard

                NovaOBProviderButtons(
                    onApple: { Task { await controller.runApple() } },
                    onGoogle: { Task { await controller.runGoogle() } }
                )

                NovaOBDivider(text: "veya")

                Button { controller.go(.emailForm) } label: {
                    HStack(spacing: 10) {
                        NovaOBIconPath(
                            path: "M2.5 4.5h19v15h-19z|M3 7.5l9 6 9-6",
                            size: 21, color: NovaOB.ink, lineWidth: 1.7
                        )
                        Text("Mail ile devam et").font(NovaOB.font(17, 500)).foregroundColor(NovaOB.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(NovaOB.line2, lineWidth: 1.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                if !controller.authError.isEmpty {
                    NovaOBErrorNote(text: controller.authError)
                }

                Spacer(minLength: 12)

                VStack(spacing: 10) {
                    NovaOBLegalLine(prefix: "Hesap oluşturarak")
                    Button(action: onLogin) {
                        Text("Zaten hesabın var mı? Giriş yap")
                            .font(NovaOB.font(15, 600))
                            .foregroundColor(NovaOB.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
            .padding(.bottom, 34)
            .frame(minHeight: UIScreen.main.bounds.height - 40, alignment: .top)
        }
        .background(NovaOB.surface.ignoresSafeArea())
    }

    private var lockCard: some View {
        HStack(spacing: 12) {
            NovaOBAnimatedLock()
                .frame(width: 38, height: 38)
                .background(NovaOB.ink, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(lockLine).font(NovaOB.font(15.5, 600))
                Text("Hesabını oluşturduğun anda profilin kalıcı olarak kaydedilir.")
                    .font(NovaOB.font(13))
                    .foregroundColor(NovaOB.muted)
                    .lineSpacing(NovaOB.lineSpacing(13, 1.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NovaOB.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NovaOBDivider: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(NovaOB.line).frame(height: 1)
            Text(text).font(NovaOB.font(13)).foregroundColor(NovaOB.muted)
            Rectangle().fill(NovaOB.line).frame(height: 1)
        }
    }
}

/// Terms + privacy line that opens the app's real legal documents.
struct NovaOBLegalLine: View {
    let prefix: String
    var alignment: TextAlignment = .leading
    @State private var document: LegalDocumentKind?

    var body: some View {
        Text(line)
            .font(NovaOB.font(12.5, 300))
            .foregroundColor(NovaOB.muted)
            .lineSpacing(NovaOB.lineSpacing(12.5, 1.45))
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .environment(\.openURL, OpenURLAction { url in
                document = url.absoluteString.hasSuffix("privacy") ? .privacy : .terms
                return .handled
            })
            .sheet(item: $document) { kind in
                LegalInfoSheet(initialDocument: kind) { document = nil }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }

    /// Inline links, black and undecorated exactly like the prototype's
    /// `a { color:#000; text-decoration:none }`.
    private var line: AttributedString {
        var result = AttributedString("\(prefix) ")
        var terms = AttributedString("Kullanım Koşulları")
        terms.link = URL(string: "isgada-legal://terms")
        terms.foregroundColor = NovaOB.ink
        var privacy = AttributedString("Gizlilik Bildirimi")
        privacy.link = URL(string: "isgada-legal://privacy")
        privacy.foregroundColor = NovaOB.ink
        result.append(terms)
        result.append(AttributedString(" ve "))
        result.append(privacy)
        result.append(AttributedString("’ni kabul edersin."))
        return result
    }
}

// MARK: - Mail ile kayıt

struct NovaOBEmailFormScreen: View {
    @ObservedObject var controller: NovaOBController
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    NovaOBBackButton { controller.go(.signup) }.padding(.leading, -12)
                    Spacer(minLength: 0)
                }

                Image("NovaOBEmailArt")
                    .resizable().scaledToFit()
                    .frame(width: 124, height: 124)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
                    .padding(.bottom, -12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Mail ile hesap oluştur")
                        .font(NovaOB.font(27, 700))
                        .tracking(-0.3)
                        .lineSpacing(NovaOB.lineSpacing(27, 1.2))
                    Text("Adresini doğrulamak için 6 haneli bir kod göndereceğiz.")
                        .font(NovaOB.font(15.5))
                        .foregroundColor(NovaOB.muted)
                        .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                fields
                Spacer(minLength: 12)

                NovaOBPrimaryButton(
                    title: controller.busy ? "İşleniyor…" : "Hesap oluştur",
                    enabled: !controller.busy,
                    showsArrow: true
                ) {
                    focus = nil
                    Task { await controller.submitSignup() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
            .padding(.bottom, 34)
            .frame(minHeight: UIScreen.main.bounds.height - 40, alignment: .top)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NovaOB.surface.ignoresSafeArea())
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                NovaOBIconPath(path: "M2.5 4.5h19v15h-19z|M3 7.5l9 6 9-6", size: 19,
                               color: NovaOB.muted2, lineWidth: 1.7)
                    .padding(.leading, 16)
                TextField("E-posta adresin", text: $controller.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .focused($focus, equals: .email)
                    .padding(.leading, 8)
            }
            .novaOBField(
                leadingInset: 0,
                border: focus == .email ? NovaOB.ink
                    : (!controller.authError.isEmpty && !NovaOBController.isValidEmail(controller.email)
                       ? NovaOB.errorBorder : NovaOB.line)
            )

            HStack(spacing: 0) {
                NovaOBIconPath(path: "M4 10.5h16v10.5H4z|M8 10.5V7.5a4 4 0 018 0v3", size: 19,
                               color: NovaOB.muted2, lineWidth: 1.7)
                    .padding(.leading, 16)
                Group {
                    if controller.showPassword {
                        TextField("Parola oluştur", text: $controller.password)
                    } else {
                        SecureField("Parola oluştur", text: $controller.password)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .padding(.leading, 8)

                Button { controller.showPassword.toggle() } label: {
                    Text(controller.showPassword ? "Gizle" : "Göster")
                        .font(NovaOB.font(14))
                        .foregroundColor(NovaOB.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .novaOBField(
                leadingInset: 0, trailingInset: 0,
                border: focus == .password ? NovaOB.ink
                    : (!controller.authError.isEmpty && !IsgPasswordRules(controller.password).valid
                       ? NovaOB.errorBorder : NovaOB.line)
            )

            NovaOBPasswordStrength(password: controller.password)

            Text("En az 8 karakter; büyük harf, küçük harf ve rakam içermeli.")
                .font(NovaOB.font(13))
                .foregroundColor(NovaOB.muted)
                .lineSpacing(NovaOB.lineSpacing(13, 1.4))
                .fixedSize(horizontal: false, vertical: true)

            if !controller.authError.isEmpty {
                NovaOBErrorNote(text: controller.authError)
            }

            Button { controller.marketing.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(controller.marketing ? NovaOB.ink : NovaOB.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(controller.marketing ? NovaOB.ink : NovaOB.line2, lineWidth: 1.5)
                        )
                        .frame(width: 24, height: 24)
                        .overlay {
                            if controller.marketing {
                                NovaOBIconPath(path: "M2 7.5l3.4 3.4L12 3.5", size: 13, color: .white,
                                               lineWidth: 2.2, viewBox: 14)
                            }
                        }
                        .padding(.top, 1)
                    Text("İSGADA güncellemeleri ve bilgilendirmelerini e-posta ile almak istiyorum. (İsteğe bağlı)")
                        .font(NovaOB.font(13.5))
                        .foregroundColor(NovaOB.muted)
                        .lineSpacing(NovaOB.lineSpacing(13.5, 1.4))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Four-bar meter plus the rule chips from the prototype.
struct NovaOBPasswordStrength: View {
    let password: String

    private struct Rule { let ok: Bool; let path: String }

    private var rules: [Rule] {
        [
            Rule(ok: password.count >= 8, path: "M4 12h16"),
            Rule(
                ok: password.range(of: "[a-zçğıöşü]", options: .regularExpression) != nil
                    && password.range(of: "[A-ZÇĞİÖŞÜ]", options: .regularExpression) != nil,
                path: "M5 18L9.5 6l4.5 12M6.8 14h5.4M17 18v-6a2.6 2.6 0 10-2.6 2.6"
            ),
            Rule(ok: password.range(of: "\\d", options: .regularExpression) != nil,
                 path: "M7 8.5L10 6.5V18M14 9a3 3 0 115.6 1.6L14 18h6"),
            Rule(ok: password.range(of: "[^A-Za-z0-9ÇĞİÖŞÜçğıöşü]", options: .regularExpression) != nil,
                 path: "M12 4.5v15M4.5 12h15M7 7l10 10M17 7L7 17")
        ]
    }

    private var score: Int { rules.filter(\.ok).count }

    private var level: (label: String, color: Color) {
        switch score {
        case 0: return password.isEmpty ? ("Parola gücü", NovaOB.muted2) : ("Çok zayıf", Color(hex: 0xB4564C))
        case 1: return ("Zayıf", Color(hex: 0xB4564C))
        case 2: return ("Orta", Color(hex: 0xC08A3E))
        case 3: return ("Güçlü", NovaOB.ink)
        default: return ("Çok güçlü", NovaOB.ink)
        }
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? level.color : NovaOB.line)
                        .frame(height: 5)
                        .animation(.easeInOut(duration: 0.26), value: score)
                }
            }
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    NovaOBIconPath(
                        path: "M12 3l7 3v5.5c0 4.3-2.9 7.7-7 9.5-4.1-1.8-7-5.2-7-9.5V6z|M8.8 12.2l2.3 2.3 4.1-4.5",
                        size: 16, color: level.color, lineWidth: 1.9
                    )
                    Text(level.label).font(NovaOB.font(13, 600)).foregroundColor(level.color)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        NovaOBIconPath(path: rule.path, size: 14,
                                       color: rule.ok ? NovaOB.ink : Color(hex: 0xADADAD), lineWidth: 2)
                            .frame(width: 26, height: 26)
                            .background(rule.ok ? Color(hex: 0xF0F0F0) : Color(hex: 0xF2F2F2), in: Circle())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Doğrulama kodu

struct NovaOBOtpScreen: View {
    @ObservedObject var controller: NovaOBController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    NovaOBBackButton { controller.go(.emailForm) }.padding(.leading, -12)
                    Spacer(minLength: 0)
                }

                Image("NovaOBOtpArt")
                    .resizable().scaledToFit()
                    .frame(width: 130, height: 130)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -12)
                    .padding(.bottom, -14)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Kodu gir")
                        .font(NovaOB.font(27, 700))
                        .tracking(-0.3)
                    Text(controller.email.novaTrimmed.isEmpty
                         ? "Kodu e-posta adresine gönderdik."
                         : "Kodu \(controller.email.novaTrimmed) adresine gönderdik.")
                        .font(NovaOB.font(15.5))
                        .foregroundColor(NovaOB.muted)
                        .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                NovaOBCodeField(
                    digits: $controller.otpDigits,
                    state: controller.otpError.isEmpty ? (controller.otpVerified ? .verified : .idle) : .invalid
                ) { code in
                    Task { await controller.verifyOtp(code) }
                }

                if !controller.otpError.isEmpty {
                    NovaOBErrorNote(text: controller.otpError)
                }
                if controller.otpVerified {
                    NovaOBInfoNote(
                        text: "Kod doğrulandı, yönlendiriliyorsun…",
                        icon: "circle:12,12,9.2|M7.8 12.3l2.9 2.9 5.5-6"
                    )
                }

                HStack(spacing: 14) {
                    Button { Task { await controller.resendCode() } } label: {
                        HStack(spacing: 8) {
                            NovaOBIconPath(path: "M20 11a8 8 0 10-2.6 5.9|M20 4.5V11h-6",
                                           size: 16, color: NovaOB.ink, lineWidth: 1.9)
                            Text("Kodu yeniden gönder").font(NovaOB.font(14.5, 600)).foregroundColor(NovaOB.ink)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(NovaOB.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if controller.resendNote {
                        Text("Yeni kod gönderildi.").font(NovaOB.font(13.5)).foregroundColor(NovaOB.ink)
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
            .padding(.bottom, 34)
            .frame(minHeight: UIScreen.main.bounds.height - 40, alignment: .top)
        }
        .background(NovaOB.surface.ignoresSafeArea())
    }
}

/// Six single-digit boxes that behave like one field: paste fills them all,
/// backspace walks back, and a full code fires `onComplete`.
struct NovaOBCodeField: View {
    enum State { case idle, invalid, verified }

    @Binding var digits: [String]
    var state: State = .idle
    let onComplete: (String) -> Void
    @FocusState private var focusedIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                TextField("", text: binding(for: index))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(NovaOB.font(24, 700))
                    .foregroundColor(NovaOB.ink)
                    .tint(NovaOB.ink)
                    .focused($focusedIndex, equals: index)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(background(index), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(border(index), lineWidth: 1.5)
                    )
            }
        }
        .onAppear { focusedIndex = 0 }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { digits.indices.contains(index) ? digits[index] : "" },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                guard !filtered.isEmpty else {
                    digits[index] = ""
                    if index > 0 { focusedIndex = index - 1 }
                    return
                }
                var next = digits
                var cursor = index
                for character in filtered {
                    guard cursor < 6 else { break }
                    next[cursor] = String(character)
                    cursor += 1
                }
                digits = next
                let code = next.joined()
                if code.count == 6 {
                    focusedIndex = nil
                    onComplete(code)
                } else {
                    focusedIndex = min(cursor, 5)
                }
            }
        )
    }

    private func border(_ index: Int) -> Color {
        switch state {
        case .invalid: return NovaOB.errorBorder
        case .verified: return NovaOB.ink
        case .idle: return digits[index].isEmpty ? NovaOB.line2 : NovaOB.ink
        }
    }

    private func background(_ index: Int) -> Color {
        switch state {
        case .invalid: return Color(hex: 0xFDF3F2)
        case .verified: return Color(hex: 0xF5F5F5)
        case .idle: return NovaOB.surface
        }
    }
}
#endif
