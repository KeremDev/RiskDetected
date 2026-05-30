import SwiftUI

struct LegalInfoSheet: View {
    let onClose: () -> Void
    @State private var selectedDocument: LegalDocumentKind = .kvkk

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                documentTabs
                LegalDocumentReader(document: selectedDocument.document)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.rdPaper)
            .navigationTitle("Yasal Bilgilendirme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
        }
    }

    private var documentTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LegalDocumentKind.allCases) { kind in
                    let active = selectedDocument == kind
                    Button {
                        selectedDocument = kind
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(kind.shortTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .foregroundStyle(active ? Color.white : Color.rdCharcoal)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(active ? Color.rdSelected : Color.rdWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(active ? Color.rdGreen.opacity(0.55) : Color.rdLine, lineWidth: active ? 1.4 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(RDPressableButtonStyle())
                    .accessibilityLabel("\(kind.title) belgesini göster")
                }
            }
        }
    }
}

private struct LegalDocumentReader: View {
    let document: LegalDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .fixedSize(horizontal: false, vertical: true)

                Text(document.fileName)
                    .rdMono(size: 10, weight: .medium)
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Color.rdLine)

            ScrollView(showsIndicators: true) {
                Text(document.text)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.rdCharcoal)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .scrollIndicators(.visible)
            .background(Color.rdWhite)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case kvkk
    case consent
    case terms
    case privacy
    case cookies

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .kvkk: return "KVKK"
        case .consent: return "Rıza"
        case .terms: return "Koşullar"
        case .privacy: return "Gizlilik"
        case .cookies: return "Çerez"
        }
    }

    var title: String {
        switch self {
        case .kvkk: return "KVKK Aydınlatma Metni"
        case .consent: return "Açık Rıza Beyanı"
        case .terms: return "Kullanım Koşulları"
        case .privacy: return "Gizlilik Politikası"
        case .cookies: return "Çerez Politikası"
        }
    }

    var fileName: String {
        switch self {
        case .kvkk: return "KVKK-Aydinlatma-ve-Acik-Riza-Metni"
        case .consent: return "Acik-Riza-Beyani"
        case .terms: return "Kullanim-Kosullari"
        case .privacy: return "Gizlilik-Politikasi"
        case .cookies: return "Cerez-Politikasi"
        }
    }

    var document: LegalDocument {
        LegalDocument(kind: self)
    }
}

private struct LegalDocument {
    let title: String
    let fileName: String
    let text: String

    init(kind: LegalDocumentKind) {
        title = kind.title
        fileName = "\(kind.fileName).md"
        text = Self.loadText(fileName: kind.fileName)
    }

    private static func loadText(fileName: String) -> String {
        let nestedURL = Bundle.main.url(
            forResource: fileName,
            withExtension: "md",
            subdirectory: "LegalDocuments"
        )
        let flatURL = Bundle.main.url(forResource: fileName, withExtension: "md")

        guard let url = nestedURL ?? flatURL else {
            return "Belge yüklenemedi. Lütfen daha sonra tekrar deneyin."
        }

        return (try? String(contentsOf: url, encoding: .utf8))
            ?? "Belge okunamadı. Lütfen daha sonra tekrar deneyin."
    }
}

#Preview {
    LegalInfoSheet(onClose: {})
}
