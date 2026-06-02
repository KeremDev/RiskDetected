import SwiftUI

struct LegalAcceptanceNotice: View {
    let fontSize: CGFloat
    let textColor: Color
    let linkColor: Color
    let accessibilityIdentifier: String

    init(
        fontSize: CGFloat = 12,
        textColor: Color = Color.rdSlate,
        linkColor: Color = Color.rdGraphite,
        accessibilityIdentifier: String = "legal.acceptance_notice"
    ) {
        self.fontSize = fontSize
        self.textColor = textColor
        self.linkColor = linkColor
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        Text(noticeText())
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func noticeText() -> AttributedString {
        var text = plain("Kaydolarak veya giriş yaparak, ")
        text.append(link("Hizmet Şartlarımızı", url: RDConfig.Web.termsURL))
        text.append(plain(", "))
        text.append(link("Gizlilik Politikamızı", url: RDConfig.Web.privacyPolicyURL))
        text.append(plain(", "))
        text.append(link("KVKK Aydınlatma Metnini", url: RDConfig.Web.kvkkURL))
        text.append(plain(" ve "))
        text.append(link("Açık Rıza Beyanını", url: RDConfig.Web.explicitConsentURL))
        text.append(plain(" kabul etmiş olursunuz."))
        return text
    }

    private func plain(_ value: String) -> AttributedString {
        var text = AttributedString(value)
        text.foregroundColor = textColor
        return text
    }

    private func link(_ value: String, url: URL) -> AttributedString {
        var text = AttributedString(value)
        text.foregroundColor = linkColor
        text.underlineStyle = .single
        text.link = url
        return text
    }
}
