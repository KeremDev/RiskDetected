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
        var text = plain("Kaydolarak veya giriş yaparak, ")
        text.append(link("Hizmet Şartlarımızı", kind: .terms))
        text.append(plain(", "))
        text.append(link("Gizlilik Politikamızı", kind: .privacy))
        text.append(plain(", "))
        text.append(link("KVKK Aydınlatma Metnini", kind: .kvkk))
        text.append(plain(" ve "))
        text.append(link("Açık Rıza Beyanını", kind: .consent))
        text.append(plain(" kabul etmiş olursunuz."))
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
