import SwiftUI

struct LegalInfoSheet: View {
    let onClose: () -> Void
    @StateObject private var legalDocuments = LegalDocumentService.shared
    @State private var selectedDocument: LegalDocumentKind

    init(initialDocument: LegalDocumentKind = .kvkk, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _selectedDocument = State(
            initialValue: RDLanguage.current == .english
                && initialDocument == .kvkk
                ? .terms
                : initialDocument
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if RDLanguage.current == .english
                    && !RDLegalReleaseGate.englishAuthAndPurchaseApproved {
                    EnglishLegalUnavailableView()
                } else {
                    documentTabs
                    LegalDocumentReader(document: legalDocuments.document(for: selectedDocument))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.rdPaper)
            .navigationTitle(
                RDLocalization.string(
                    "legal.info.title",
                    table: .legal,
                    fallback: "Yasal Bilgilendirme"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
        }
        .task {
            guard RDLanguage.current == .turkish
                    || RDLegalReleaseGate.englishAuthAndPurchaseApproved
            else { return }
            await legalDocuments.refreshIfNeeded(
                userID: SupabaseService.shared.currentUserID,
                userCreatedAt: SupabaseService.shared.client.auth.currentUser?.createdAt
            )
        }
    }

    private var documentTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(legalDocuments.availableKinds) { kind in
                    let active = selectedDocument == kind
                    Button {
                        selectedDocument = kind
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(kind.shortTitle)
                            .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
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
                    .accessibilityLabel(
                        RDLocalization.format(
                            "legal.document.show.accessibility",
                            table: .legal,
                            fallback: "%@ belgesini göster",
                            arguments: [kind.title]
                        )
                    )
                }
            }
        }
    }
}

private struct EnglishLegalUnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.shield")
                .font(RDTypography.font(size: RDFontScale.size(28), weight: .semibold))
                .foregroundStyle(Color.rdGreen)

            Text(
                RDLocalization.string(
                    "legal.english_unavailable.title",
                    table: .legal,
                    fallback: "İngilizce yasal metinler henüz kullanıma hazır değil"
                )
            )
            .font(RDTypography.font(size: RDFontScale.size(20), weight: .bold, design: .rounded))
            .foregroundStyle(Color.rdBlack)

            Text(
                RDLocalization.string(
                    "legal.english_unavailable.message",
                    table: .legal,
                    fallback: "İngilizce Kullanım Koşulları ve Gizlilik Politikası hukuk ve dil incelemesi tamamlanana kadar bu sürümde yayımlanmaz."
                )
            )
            .font(RDTypography.font(size: RDFontScale.size(14), design: .rounded))
            .foregroundStyle(Color.rdCharcoal)

            Text(
                RDLocalization.string(
                    "legal.english_unavailable.action",
                    table: .legal,
                    fallback: "Türkçe metinleri görüntülemek için uygulama dilini iOS Ayarları’ndan Türkçe seçebilirsin."
                )
            )
            .font(RDTypography.font(size: RDFontScale.size(13), design: .rounded))
            .foregroundStyle(Color.rdSlate)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct LegalDocumentReader: View {
    let document: LegalDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(RDTypography.font(size: RDFontScale.size(17), weight: .bold, design: .rounded))
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
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .regular, design: .rounded))
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

#Preview {
    LegalInfoSheet(onClose: {})
}
