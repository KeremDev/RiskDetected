import SwiftUI

struct LegalInfoSheet: View {
    let onClose: () -> Void
    @StateObject private var legalDocuments = LegalDocumentService.shared
    @State private var selectedDocument: LegalDocumentKind

    init(initialDocument: LegalDocumentKind = .kvkk, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _selectedDocument = State(initialValue: initialDocument)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                documentTabs
                LegalDocumentReader(document: legalDocuments.document(for: selectedDocument))
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
        .task {
            await legalDocuments.refreshIfNeeded(
                userID: SupabaseService.shared.currentUserID,
                userCreatedAt: SupabaseService.shared.client.auth.currentUser?.createdAt
            )
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
                            .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(13), weight: .regular, design: .rounded))
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
