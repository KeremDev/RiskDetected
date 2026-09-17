import SwiftUI
import UniformTypeIdentifiers

/// D7 file entry surface. Storage location and inspection verdict never come
/// from this view; it submits bytes to the server-owned intent flow.
struct IsgWorkspaceFileCreateEditor: View {
    @ObservedObject var store: IsgWorkspaceStore
    let onDone: () -> Void
    @State private var title = ""
    @State private var category = "other"
    @State private var filename: String?
    @State private var payload: Data?
    @State private var picking = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.novaCelebrate) private var celebrate

    private let categories = [
        "company_logo", "risk_assessment", "emergency_plan", "training_material",
        "inspection_report", "measurement_report", "accident_record", "board_document",
        "handover_form", "personnel_document", "contract", "permit_form", "visit_evidence",
        "notebook_archive", "other"
    ]
    private let types = ["pdf", "doc", "docx", "xls", "xlsx", "csv", "jpg", "jpeg",
                         "png", "webp", "avif", "heic", "heif"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: RDLocalization.string(
                    "localizable.nova.workspace.file.add", table: .localizable,
                    fallback: "Dosya ekle"), symbol: "folder.badge.plus",
                    subtitle: RDLocalization.string(
                        "localizable.nova.workspace.file.add.detail", table: .localizable,
                        fallback: "Dosya doğrulandıktan sonra seçili firmanın arşivine eklenir."))

                Button { picking = true } label: {
                    NovaCard(padding: 14) {
                        HStack(spacing: 11) {
                            NovaIcon(symbol: payload == nil ? "doc.badge.plus" : "doc.fill", size: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                NovaText(text: filename ?? RDLocalization.string(
                                    "localizable.nova.workspace.file.choose", table: .localizable,
                                    fallback: "Dosya seç"), style: .bodyStrong)
                                NovaText(text: RDLocalization.string(
                                    "localizable.nova.workspace.file.formats", table: .localizable,
                                    fallback: "PDF, Office, CSV ve görsel · en fazla 50 MB"), style: .metaQuiet)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                        }.contentShape(Rectangle())
                    }
                }.buttonStyle(.plain)

                if payload != nil {
                    TextField(RDLocalization.string(
                        "localizable.nova.workspace.file.title", table: .localizable,
                        fallback: "Dosya başlığı"), text: $title)
                        .font(NovaFont.font(.body)).padding(14).novaControlBackground(cornerRadius: 14)
                    Picker(RDLocalization.string(
                        "localizable.nova.workspace.file.category", table: .localizable,
                        fallback: "Kategori"), selection: $category) {
                            ForEach(categories, id: \.self) { value in Text(categoryTitle(value)).tag(value) }
                        }
                        .pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                }
                if let error { NovaHelpHint(text: error) }
                NovaCompactActionButton(title: saving ? RDLocalization.string(
                    "localizable.nova.workspace.file.uploading", table: .localizable,
                    fallback: "Dosya doğrulanıyor…") : RDLocalization.string(
                        "localizable.nova.workspace.file.save", table: .localizable,
                        fallback: "Dosyayı ekle"), symbol: "arrow.up.doc", prominent: true,
                    enabled: canSave && !saving) { save() }
            }.padding(18).novaPopupContentSize()
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: types,
                      allowsMultipleSelection: false) { take($0) }
    }

    private var canSave: Bool {
        payload != nil && filename != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func take(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard (1...52_428_800).contains(data.count) else {
                throw IsgWorkspaceAPIFailure.invalidRequest
            }
            filename = url.lastPathComponent
            payload = data
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
            error = nil
        } catch {
            payload = nil; filename = nil
            self.error = RDLocalization.string(
                "localizable.nova.workspace.file.read.failed", table: .localizable,
                fallback: "Dosya okunamadı veya 50 MB sınırını aşıyor.")
        }
    }

    private func save() {
        guard let payload, let filename, canSave else { return }
        saving = true; error = nil
        Task { @MainActor in
            do {
                _ = try await store.uploadFile(mutationID: UUID(), title: title,
                                               filename: filename, category: category, data: payload)
                celebrate(NovaSuccessMessage.recordSaved(RDLocalization.string(
                    "localizable.nova.workspace.file.saved.subject", table: .localizable,
                    fallback: "Dosya")))
                onDone()
            } catch {
                self.error = RDLocalization.string(
                    "localizable.nova.workspace.file.save.failed", table: .localizable,
                    fallback: "Dosya eklenemedi. Dosya türünü ve bağlantınızı kontrol edip yeniden deneyin.")
            }
            saving = false
        }
    }

    private func categoryTitle(_ value: String) -> String {
        let names: [String: String] = [
            "company_logo": "Firma logosu", "risk_assessment": "Risk değerlendirmesi",
            "emergency_plan": "Acil durum planı", "training_material": "Eğitim belgesi",
            "inspection_report": "Kontrol raporu", "measurement_report": "Ölçüm raporu",
            "accident_record": "Kaza kaydı", "board_document": "Kurul belgesi",
            "handover_form": "Teslim formu", "personnel_document": "Personel belgesi",
            "contract": "Sözleşme", "permit_form": "İzin formu",
            "visit_evidence": "Ziyaret kanıtı", "notebook_archive": "Defter arşivi",
            "other": "Diğer"
        ]
        return names[value] ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
