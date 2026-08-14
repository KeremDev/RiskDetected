import SwiftUI

struct LegalAcceptanceNotice: View {
    let fontSize: CGFloat
    let textColor: Color
    let linkColor: Color
    let accessibilityIdentifier: String
    let onOpenDocument: (LegalDocumentKind) -> Void

    init(
        fontSize: CGFloat = 12,
        textColor: Color = Color.rdSlate,
        linkColor: Color = Color.rdGraphite,
        accessibilityIdentifier: String = "legal.acceptance_notice",
        onOpenDocument: @escaping (LegalDocumentKind) -> Void = { _ in }
    ) {
        self.fontSize = fontSize
        self.textColor = textColor
        self.linkColor = linkColor
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onOpenDocument = onOpenDocument
    }

    var body: some View {
        Text(noticeText())
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(accessibilityIdentifier)
            .environment(\.openURL, OpenURLAction { url in
                guard let kind = LegalDocumentKind(internalURL: url) else {
                    return .systemAction
                }
                onOpenDocument(kind)
                return .handled
            })
    }

    private func noticeText() -> AttributedString {
        if RDLanguage.current == .english {
            var text = plain(
                RDLocalization.string(
                    "legal.acceptance.en.prefix",
                    table: .legal,
                    fallback: "By signing up or signing in, you accept the "
                )
            )
            text.append(link(
                RDLocalization.string(
                    "legal.document.terms.title",
                    table: .legal,
                    fallback: "Kullanım Koşulları"
                ),
                kind: .terms
            ))
            text.append(plain(
                RDLocalization.string(
                    "legal.acceptance.en.privacy_joiner",
                    table: .legal,
                    fallback: ", acknowledge the "
                )
            ))
            text.append(link(
                RDLocalization.string(
                    "legal.document.privacy.title",
                    table: .legal,
                    fallback: "Gizlilik Politikası"
                ),
                kind: .privacy
            ))
            text.append(plain(
                RDLocalization.string(
                    "legal.acceptance.en.consent_joiner",
                    table: .legal,
                    fallback: " and the "
                )
            ))
            text.append(link(
                RDLocalization.string(
                    "legal.acceptance.en.ai_notice",
                    table: .legal,
                    fallback: "AI and Data Processing Notice"
                ),
                kind: .consent
            ))
            text.append(plain(
                RDLocalization.string(
                    "legal.acceptance.en.suffix",
                    table: .legal,
                    fallback: "."
                )
            ))
            return text
        }
        var text = plain(RDLocalization.string("legal.legal.acceptance.notice.kaydolarak.veya.giris.yaparak.c5c76f3e", table: .legal, fallback: "Kaydolarak veya giriş yaparak,"))
        text.append(link(RDLocalization.string("legal.legal.acceptance.notice.hizmet.sartlarimizi.c5c14c41", table: .legal, fallback: "Hizmet Şartlarımızı"), kind: .terms))
        text.append(plain(", "))
        text.append(link(RDLocalization.string("legal.legal.acceptance.notice.gizlilik.politikamizi.ab642b86", table: .legal, fallback: "Gizlilik Politikamızı"), kind: .privacy))
        text.append(plain(", "))
        text.append(link(RDLocalization.string("legal.legal.acceptance.notice.kvkk.aydinlatma.metnini.f64fcf53", table: .legal, fallback: "KVKK Aydınlatma Metnini"), kind: .kvkk))
        text.append(plain(" ve "))
        text.append(link(RDLocalization.string("legal.legal.acceptance.notice.acik.riza.beyanini.ae108532", table: .legal, fallback: "Açık Rıza Beyanını"), kind: .consent))
        text.append(plain(RDLocalization.string("legal.legal.acceptance.notice.kabul.etmis.olursunuz.fa5d4328", table: .legal, fallback: "kabul etmiş olursunuz.")))
        return text
    }

    private func plain(_ value: String) -> AttributedString {
        var text = AttributedString(value)
        text.foregroundColor = textColor
        return text
    }

    private func link(_ value: String, kind: LegalDocumentKind) -> AttributedString {
        var text = AttributedString(value)
        text.foregroundColor = linkColor
        text.underlineStyle = .single
        text.link = kind.internalURL
        return text
    }
}
