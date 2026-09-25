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
            .buttonStyle(NovaPressStyle())

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
            .buttonStyle(NovaPressStyle())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A signup form can sit on screen for a while, and this ran every
        // frame the whole time regardless of the setting whose entire job is
        // to stop exactly this kind of idle loop. `paused` keeps the same
        // schedule type but stops the per-frame updates, so the lock sits
        // closed instead of perpetually lifting its shackle.
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
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

    @State private var pageHeight: CGFloat = 0

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
                .buttonStyle(NovaPressStyle())

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
                    .buttonStyle(NovaPressStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, NovaOB.padTop(70))
            .padding(.bottom, NovaOB.padBottom(34))
            .frame(minHeight: pageHeight, alignment: .top)
        }
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
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

    var body: some View {
        NovaOBSignupPage(
            email: $controller.email, password: $controller.password,
            showPassword: $controller.showPassword, marketing: $controller.marketing,
            error: controller.authError, busy: controller.busy,
            onBack: { controller.go(.signup) },
            onLogin: { controller.go(.login) },
            onSubmit: { Task { await controller.submitSignup() } }
        )
    }
}

/// "Mail ile hesap oluştur": the one place a new password account starts, from the
/// funnel and from the login screen. The code page follows it.
struct NovaOBSignupPage: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var showPassword: Bool
    /// The optional updates checkbox; the login screen does not show it.
    var marketing: Binding<Bool>?
    let error: String
    let busy: Bool
    let onBack: () -> Void
    let onLogin: () -> Void
    let onSubmit: () -> Void
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    @State private var pageHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        NovaOBBackButton(action: onBack).padding(.leading, -12)
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
                        title: busy ? "İşleniyor…" : "Hesap oluştur",
                        enabled: !busy,
                        showsArrow: true
                    ) {
                        emailFocused = false
                        passwordFocused = false
                        onSubmit()
                    }
                    .accessibilityIdentifier("nova.signup.submit")

                    Button(action: onLogin) {
                        Text("Zaten hesabın var mı? Giriş yap")
                            .font(NovaOB.font(14.5, 600))
                            .foregroundColor(NovaOB.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(NovaPressStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, NovaOB.padTop(70))
                .padding(.bottom, NovaOB.padBottom(34))
                .frame(minHeight: pageHeight, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            .novaOBRevealsPasswordRules(when: passwordFocused, proxy: proxy)
        }
        .background(NovaOB.surface.ignoresSafeArea())
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaOBEmailField(email: $email, focused: $emailFocused, showsError: !error.isEmpty)

            NovaOBNewPasswordField(placeholder: "Parola oluştur", password: $password,
                                   showPassword: $showPassword, focused: $passwordFocused,
                                   showsError: !error.isEmpty)

            if !error.isEmpty {
                NovaOBErrorNote(text: error)
            }

            if let marketing {
                Button { marketing.wrappedValue.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(marketing.wrappedValue ? NovaOB.ink : NovaOB.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(marketing.wrappedValue ? NovaOB.ink : NovaOB.line2, lineWidth: 1.5)
                            )
                            .frame(width: 24, height: 24)
                            .overlay {
                                if marketing.wrappedValue {
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
                .buttonStyle(NovaPressStyle())
            }
        }
    }
}

/// The mail field of the signup and reset pages.
struct NovaOBEmailField: View {
    @Binding var email: String
    var focused: FocusState<Bool>.Binding
    /// Marks the field when the page shows an error and the address is not valid.
    let showsError: Bool

    var body: some View {
        HStack(spacing: 0) {
            NovaOBIconPath(path: "M2.5 4.5h19v15h-19z|M3 7.5l9 6 9-6", size: 19,
                           color: NovaOB.muted2, lineWidth: 1.7)
                .padding(.leading, 16)
            TextField("E-posta adresin", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .focused(focused)
                .padding(.leading, 8)
        }
        .novaOBField(
            leadingInset: 0,
            border: focused.wrappedValue ? NovaOB.ink
                : (showsError && !NovaOBController.isValidEmail(email) ? NovaOB.errorBorder : NovaOB.line)
        )
    }
}

/// A password being chosen, on signup and at the end of a reset. The rules under it are
/// checked as the user types: a met rule turns green, a missing one red, and the field turns
/// green once all are met. Pages scroll `rulesID` into view when the field is focused, so the
/// keyboard does not hide the rules.
struct NovaOBNewPasswordField: View {
    static let rulesID = "nova.password.rules"

    let placeholder: String
    @Binding var password: String
    @Binding var showPassword: Bool
    var focused: FocusState<Bool>.Binding
    /// A refused submit: missing rules turn red even with nothing typed.
    let showsError: Bool

    private var border: Color {
        if IsgPasswordRules(password).valid { return NovaOB.successBorder }
        if !password.isEmpty || showsError { return NovaOB.errorBorder }
        return focused.wrappedValue ? NovaOB.ink : NovaOB.line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                NovaOBIconPath(path: "M4 10.5h16v10.5H4z|M8 10.5V7.5a4 4 0 018 0v3", size: 19,
                               color: NovaOB.muted2, lineWidth: 1.7)
                    .padding(.leading, 16)
                Group {
                    if showPassword {
                        TextField(placeholder, text: $password)
                    } else {
                        SecureField(placeholder, text: $password)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focused)
                .padding(.leading, 8)

                Button { showPassword.toggle() } label: {
                    Text(showPassword ? "Gizle" : "Göster")
                        .font(NovaOB.font(14))
                        .foregroundColor(NovaOB.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
                .buttonStyle(NovaPressStyle())
                .padding(.trailing, 8)
            }
            .novaOBField(leadingInset: 0, trailingInset: 0, border: border)
            .animation(.easeInOut(duration: 0.2), value: border)

            NovaOBPasswordRules(password: password, flagged: showsError)
                .padding(.bottom, 12)
                .id(Self.rulesID)
        }
    }
}

/// The four rules of `IsgPasswordRules`, two per row. Neutral while nothing is typed.
struct NovaOBPasswordRules: View {
    let password: String
    let flagged: Bool

    var body: some View {
        let rules = IsgPasswordRules(password)
        let marked = !password.isEmpty || flagged
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
            GridRow {
                rule(rules.minimumCharacters && rules.maximumBytes,
                     rules.maximumBytes ? "En az 8 karakter" : "En fazla 72 karakter",
                     id: "length", marked: marked)
                rule(rules.uppercase, "Büyük harf", id: "upper", marked: marked)
            }
            GridRow {
                rule(rules.lowercase, "Küçük harf", id: "lower", marked: marked)
                rule(rules.digit, "Rakam", id: "digit", marked: marked)
            }
        }
    }

    private func rule(_ met: Bool, _ title: String, id: String, marked: Bool) -> some View {
        let color = met ? NovaOB.successInk : (marked ? NovaOB.errorInk : NovaOB.muted2)
        return HStack(spacing: 7) {
            ZStack {
                if met {
                    Circle().fill(NovaOB.successInk)
                    NovaOBIconPath(path: "M7 12.4l3.2 3.2L17 8.8", size: 12, color: .white, lineWidth: 2.6)
                } else if marked {
                    Circle().strokeBorder(NovaOB.errorInk, lineWidth: 1.5)
                    NovaOBIconPath(path: "M8.5 8.5l7 7|M15.5 8.5l-7 7", size: 10, color: NovaOB.errorInk, lineWidth: 2.4)
                } else {
                    Circle().strokeBorder(NovaOB.line2, lineWidth: 1.5)
                }
            }
            .frame(width: 17, height: 17)
            Text(title)
                .font(NovaOB.font(13.5, 500))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: met)
        .accessibilityElement(children: .combine)
        .accessibilityValue(met ? "tamam" : "eksik")
        .accessibilityIdentifier("nova.password.rule.\(id)")
    }
}

// MARK: - Şifre sıfırlama

/// "Şifreni belirle", step one: the address the 6-digit code goes to. It serves a forgotten
/// password and an account that never had one (everyone signed in with mailed codes before
/// passwords). The code page follows, then `NovaOBNewPasswordPage`.
struct NovaOBResetEmailPage: View {
    @Binding var email: String
    let error: String
    let busy: Bool
    let onBack: () -> Void
    let onSubmit: () -> Void
    @FocusState private var emailFocused: Bool
    @State private var pageHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    NovaOBBackButton(action: onBack).padding(.leading, -12)
                    Spacer(minLength: 0)
                }

                Image("NovaOBEmailArt")
                    .resizable().scaledToFit()
                    .frame(width: 124, height: 124)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
                    .padding(.bottom, -12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Şifreni belirle")
                        .font(NovaOB.font(27, 700))
                        .tracking(-0.3)
                        .lineSpacing(NovaOB.lineSpacing(27, 1.2))
                    Text("Mailine 6 haneli bir kod gönderelim; kodu girince yeni şifreni belirlersin.")
                        .font(NovaOB.font(15.5))
                        .foregroundColor(NovaOB.muted)
                        .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                NovaOBEmailField(email: $email, focused: $emailFocused, showsError: !error.isEmpty)

                if !error.isEmpty { NovaOBErrorNote(text: error) }

                HStack(alignment: .top, spacing: 9) {
                    NovaOBIconPath(path: "circle:12,12,9.2|M12 11v5.2|M12 7.8v.1", size: 15,
                                   color: NovaOB.muted2, lineWidth: 1.8)
                        .padding(.top, 1)
                    Text("Apple veya Google ile kaydolduysan şifre gerekmez; o butonla giriş yap.")
                        .font(NovaOB.font(12.5))
                        .foregroundColor(NovaOB.muted)
                        .lineSpacing(NovaOB.lineSpacing(12.5, 1.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NovaOB.fill3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer(minLength: 12)

                NovaOBPrimaryButton(title: busy ? "Gönderiliyor…" : "Kod gönder", enabled: !busy, showsArrow: true) {
                    emailFocused = false
                    onSubmit()
                }
                .accessibilityIdentifier("nova.reset.send")

                Button(action: onBack) {
                    Text("Girişe dön")
                        .font(NovaOB.font(14.5, 600))
                        .foregroundColor(NovaOB.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(NovaPressStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, NovaOB.padTop(70))
            .padding(.bottom, NovaOB.padBottom(34))
            .frame(minHeight: pageHeight, alignment: .top)
        }
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .background(NovaOB.surface.ignoresSafeArea())
    }
}

/// Reset, last step: the new password, once the code from the reset mail is verified.
struct NovaOBNewPasswordPage: View {
    @Binding var password: String
    @Binding var showPassword: Bool
    let error: String
    let busy: Bool
    let onBack: () -> Void
    let onSubmit: () -> Void
    @FocusState private var passwordFocused: Bool
    @State private var pageHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        NovaOBBackButton(action: onBack).padding(.leading, -12)
                        Spacer(minLength: 0)
                    }

                    Image("NovaOBEmailArt")
                        .resizable().scaledToFit()
                        .frame(width: 124, height: 124)
                        .frame(maxWidth: .infinity)
                        .padding(.top, -10)
                        .padding(.bottom, -12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Yeni şifreni belirle")
                            .font(NovaOB.font(27, 700))
                            .tracking(-0.3)
                            .lineSpacing(NovaOB.lineSpacing(27, 1.2))
                        Text("Kod doğrulandı. Bundan sonra bu şifreyle giriş yapacaksın.")
                            .font(NovaOB.font(15.5))
                            .foregroundColor(NovaOB.muted)
                            .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NovaOBNewPasswordField(placeholder: "Yeni şifre", password: $password,
                                           showPassword: $showPassword, focused: $passwordFocused,
                                           showsError: !error.isEmpty)

                    if !error.isEmpty { NovaOBErrorNote(text: error) }

                    Spacer(minLength: 12)

                    NovaOBPrimaryButton(title: busy ? "Kaydediliyor…" : "Şifreyi kaydet", enabled: !busy, showsArrow: true) {
                        passwordFocused = false
                        onSubmit()
                    }
                    .accessibilityIdentifier("nova.reset.save")
                }
                .padding(.horizontal, 24)
                .padding(.top, NovaOB.padTop(70))
                .padding(.bottom, NovaOB.padBottom(34))
                .frame(minHeight: pageHeight, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            .novaOBRevealsPasswordRules(when: passwordFocused, proxy: proxy)
        }
        .background(NovaOB.surface.ignoresSafeArea())
    }
}

extension View {
    /// Once the keyboard is up for a new password, scrolls the rules under the field above it.
    func novaOBRevealsPasswordRules(when focused: Bool, proxy: ScrollViewProxy) -> some View {
        onChange(of: focused) { isFocused in
            guard isFocused else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(NovaOBNewPasswordField.rulesID, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Doğrulama kodu

struct NovaOBOtpScreen: View {
    @ObservedObject var controller: NovaOBController

    var body: some View {
        NovaOBCodePage(
            email: controller.email, digits: $controller.otpDigits,
            error: controller.otpError, retryable: controller.otpRetryable, checking: controller.busy,
            verified: controller.otpVerified,
            verifiedNote: "Kod doğrulandı, yönlendiriliyorsun…", resendNote: controller.resendNote,
            onBack: { controller.go(.emailForm) },
            onEdit: controller.clearOtpError,
            onComplete: { code in Task { await controller.verifyOtp(code) } },
            onResend: { Task { await controller.resendCode() } }
        )
    }
}

/// "Kodu gir": a mailed code as its own page. The funnel and the login screen use it for
/// the signup code, the login screen also for the reset code. A full code is checked on its own;
/// a right one turns the boxes green and the owner moves on, a wrong one turns them red with the
/// digits kept for fixing, and a lost connection offers "Tekrar dene" instead.
struct NovaOBCodePage: View {
    let email: String
    @Binding var digits: [String]
    let error: String
    /// The error is a lost connection, not a wrong code: the boxes stay neutral.
    var retryable = false
    var checking = false
    let verified: Bool
    let verifiedNote: String
    /// Shown next to the resend button once a resend has been answered.
    let resendNote: String
    let onBack: () -> Void
    var onEdit: () -> Void = {}
    let onComplete: (String) -> Void
    let onResend: () -> Void

    @State private var pageHeight: CGFloat = 0
    private static let helpID = "nova.code.help"

    private var fieldState: NovaOBCodeField.State {
        if verified { return .verified }
        return error.isEmpty || retryable ? .idle : .invalid
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        NovaOBBackButton(action: onBack).padding(.leading, -12)
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
                        Text(email.novaTrimmed.isEmpty
                             ? "Kodu e-posta adresine gönderdik."
                             : "Kodu \(email.novaTrimmed) adresine gönderdik.")
                            .font(NovaOB.font(15.5))
                            .foregroundColor(NovaOB.muted)
                            .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NovaOBCodeField(digits: $digits, state: fieldState, onEdit: onEdit, onComplete: onComplete)

                    VStack(alignment: .leading, spacing: 14) {
                        if checking {
                            HStack(spacing: 9) {
                                NovaOBSpinner(size: 15)
                                Text("Kod kontrol ediliyor…")
                                    .font(NovaOB.font(13.5))
                                    .foregroundColor(NovaOB.muted)
                            }
                        }
                        if !error.isEmpty {
                            NovaOBErrorNote(text: error)
                            if retryable {
                                Button { onComplete(digits.joined()) } label: {
                                    Text("Tekrar dene")
                                        .font(NovaOB.font(14.5, 600))
                                        .foregroundColor(NovaOB.ink)
                                        .padding(.horizontal, 14)
                                        .frame(height: 40)
                                        .background(NovaOB.fill, in: Capsule())
                                }
                                .buttonStyle(NovaPressStyle())
                            }
                        }
                        if verified {
                            NovaOBInfoNote(text: verifiedNote, icon: "circle:12,12,9.2|M7.8 12.3l2.9 2.9 5.5-6")
                        }

                        HStack(spacing: 14) {
                            Button(action: onResend) {
                                HStack(spacing: 8) {
                                    NovaOBIconPath(path: "M20 11a8 8 0 10-2.6 5.9|M20 4.5V11h-6",
                                                   size: 16, color: NovaOB.ink, lineWidth: 1.9)
                                    Text("Kodu yeniden gönder").font(NovaOB.font(14.5, 600)).foregroundColor(NovaOB.ink)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(NovaOB.fill, in: Capsule())
                            }
                            .buttonStyle(NovaPressStyle())

                            if !resendNote.isEmpty {
                                Text(resendNote).font(NovaOB.font(13.5)).foregroundColor(NovaOB.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }

                        Text("Kod gelmediyse spam klasörünü kontrol et.")
                            .font(NovaOB.font(13))
                            .foregroundColor(NovaOB.muted2)
                    }
                    .padding(.bottom, 12)
                    .id(Self.helpID)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, NovaOB.padTop(70))
                .padding(.bottom, NovaOB.padBottom(34))
                .frame(minHeight: pageHeight, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            // The keyboard stays up after a refused code; keep the warning and resend in sight.
            .onChange(of: error) { value in
                guard !value.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.helpID, anchor: .bottom) }
            }
        }
        .background(NovaOB.surface.ignoresSafeArea())
    }
}

/// Six digit boxes backed by one UIKit text field that never holds text and reports every key
/// instead (`NovaOBCodeKeys`), so the boxes own the digits and which one is selected. Typing
/// fills the selected box and moves on; backspace clears it, or the nearest filled one before it;
/// a tap selects any box, so one wrong digit of a refused code can be replaced; paste and
/// one-time-code AutoFill fill all six. A full code fires `onComplete` after every change, so a
/// fixed digit is checked again without a button. (Six separately focused fields handed first
/// responder back and forth and dropped keys on the iOS 26.5 simulator.)
struct NovaOBCodeField: View {
    enum State { case idle, invalid, verified }

    @Binding var digits: [String]
    var state: State = .idle
    /// Any change the user makes; owners clear a shown error with it.
    var onEdit: () -> Void = {}
    let onComplete: (String) -> Void
    @SwiftUI.State private var cursor = 0
    @SwiftUI.State private var focused = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                box(index)
                    .contentShape(Rectangle())
                    .onTapGesture { select(index) }
                    .accessibilityHidden(true)
            }
        }
        .background(
            NovaOBCodeKeys(focused: $focused, value: digits.joined(), onInsert: insert, onDelete: deleteBackward)
                .frame(width: 1, height: 1)
                .opacity(0.02)
        )
        .onAppear {
            cursor = firstEmpty ?? 5
            focused = true
        }
        // A new code (resend) empties the boxes: start again at the first one, unless typing
        // has already begun by the time this runs.
        .onChange(of: digits) { value in
            if value.allSatisfy(\.isEmpty), digits.allSatisfy(\.isEmpty) {
                cursor = 0
                focused = true
            }
        }
    }

    private var firstEmpty: Int? { digits.firstIndex(where: \.isEmpty) }

    private func box(_ index: Int) -> some View {
        let selected = focused && index == cursor && state != .verified
        return Text(digits.indices.contains(index) ? digits[index] : "")
            .font(NovaOB.font(24, 700))
            .foregroundColor(NovaOB.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .overlay {
                if selected && digits[index].isEmpty {
                    RoundedRectangle(cornerRadius: 1).fill(NovaOB.ink).frame(width: 2, height: 26)
                }
            }
            .background(background(index, selected: selected),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(border(index, selected: selected), lineWidth: selected ? 2.2 : 1.5)
            )
            .animation(.easeInOut(duration: 0.18), value: state)
    }

    private func select(_ index: Int) {
        guard state != .verified else { return }
        // A filled box can be replaced; past the first empty one there is nothing to edit yet.
        cursor = digits[index].isEmpty ? (firstEmpty ?? index) : index
        focused = true
    }

    private func insert(_ text: String) {
        guard state != .verified else { return }
        let entered = text.filter(\.isNumber).map(String.init)
        guard !entered.isEmpty else { return }
        var next = digits
        if entered.count >= 6 {
            // Paste or AutoFill: the whole code.
            next = Array(entered.prefix(6))
            cursor = 5
        } else {
            var index = cursor
            for digit in entered {
                next[index] = digit
                if index == 5 { break }
                index += 1
            }
            cursor = index
        }
        commit(next)
    }

    /// Clears the selected box, else the nearest filled one before it, else the last filled one:
    /// holding backspace always ends with every box empty, wherever the selection was.
    private func deleteBackward() {
        guard state != .verified else { return }
        var next = digits
        if next[cursor].isEmpty {
            let filled = next.indices.filter { !next[$0].isEmpty }
            guard let target = filled.last(where: { $0 < cursor }) ?? filled.last else { return }
            cursor = target
        }
        next[cursor] = ""
        commit(next)
    }

    private func commit(_ next: [String]) {
        guard next != digits else { return }
        digits = next
        onEdit()
        if next.allSatisfy({ !$0.isEmpty }) { onComplete(next.joined()) }
    }

    private func border(_ index: Int, selected: Bool) -> Color {
        switch state {
        case .verified: return NovaOB.successBorder
        case .invalid: return selected ? NovaOB.errorInk : NovaOB.errorBorder
        case .idle: return selected || !digits[index].isEmpty ? NovaOB.ink : NovaOB.line2
        }
    }

    private func background(_ index: Int, selected: Bool) -> Color {
        switch state {
        case .verified: return Color(hex: 0xEEF7F1)
        case .invalid: return Color(hex: 0xFDF3F2)
        case .idle: return selected && !digits[index].isEmpty ? NovaOB.fill3 : NovaOB.surface
        }
    }
}

/// The keyboard side of `NovaOBCodeField`: a UIKit text field that refuses every edit and reports
/// it, so backspace on an empty field still arrives and nothing it holds can drift from the boxes.
private struct NovaOBCodeKeys: UIViewRepresentable {
    @Binding var focused: Bool
    let value: String
    let onInsert: (String) -> Void
    let onDelete: () -> Void

    func makeUIView(context: Context) -> KeyField {
        let field = KeyField()
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.autocorrectionType = .no
        field.textColor = .clear
        field.tintColor = .clear
        field.delegate = context.coordinator
        field.accessibilityLabel = "Doğrulama kodu"
        field.onDelete = { [weak coordinator = context.coordinator] in coordinator?.parent.onDelete() }
        return field
    }

    func updateUIView(_ field: KeyField, context: Context) {
        context.coordinator.parent = self
        field.accessibilityValue = value
        if focused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !focused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NovaOBCodeKeys
        init(_ parent: NovaOBCodeKeys) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if !string.isEmpty { parent.onInsert(string) }
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.focused { parent.focused = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.focused { parent.focused = false }
        }
    }

    final class KeyField: UITextField {
        var onDelete: (() -> Void)?
        override func deleteBackward() { onDelete?() }
        override func caretRect(for position: UITextPosition) -> CGRect { .zero }
        override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
    }
}
#endif
