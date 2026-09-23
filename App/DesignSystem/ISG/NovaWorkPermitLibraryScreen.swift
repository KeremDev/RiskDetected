import SwiftUI
import UniformTypeIdentifiers

private struct NovaWorkPermitWordDocument: FileDocument {
    static let docxType = UTType(filenameExtension: "docx") ?? .data
    static var readableContentTypes: [UTType] { [docxType] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct NovaWorkPermitTemplate: Decodable, Identifiable {
    let code: String
    let title: String
    let usage: String
    let jobs: [String]
    let sectors: [String]
    let filename: String
    let note: String

    var id: String { code }

    var searchText: String {
        ([code, title, usage, note] + jobs + sectors).joined(separator: " ")
    }

    var fileURL: URL? {
        let base = String(filename.dropLast(".docx".count))
        return Bundle.main.url(forResource: base, withExtension: "docx",
                               subdirectory: "WorkPermitAssets/work_permits")
            ?? Bundle.main.url(forResource: base, withExtension: "docx")
    }
}

/// A read-only, bundled sample library. No company record or permit approval is created here.
struct NovaWorkPermitLibraryScreen: View {
    let onBack: () -> Void
    @State private var query = ""
    @State private var sector: String?
    @State private var job: String?
    @State private var openFilter: String?
    @State private var exportDocument: NovaWorkPermitWordDocument?
    @State private var exportName = ""
    @State private var exporting = false
    @State private var exportError: String?

    private let templates: [NovaWorkPermitTemplate] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json",
                                        subdirectory: "WorkPermitAssets/work_permits")
                ?? Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([NovaWorkPermitTemplate].self, from: data)
        else { return [] }
        return entries.sorted { $0.code < $1.code }
    }()

    private var sectors: [String] { Array(Set(templates.flatMap(\.sectors)).subtracting(["Tüm sektörler"])).sorted() }
    private var jobs: [String] { Array(Set(templates.flatMap(\.jobs))).sorted() }

    private func searchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    private var visible: [NovaWorkPermitTemplate] {
        let words = searchKey(query).split(whereSeparator: \.isWhitespace).map(String.init)
        return templates.filter { item in
            (sector == nil || item.sectors.contains(sector!) || item.sectors.contains("Tüm sektörler"))
                && (job == nil || item.jobs.contains(job!))
                && words.allSatisfy { searchKey(item.searchText).contains($0) }
        }
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: "Çalışma İzni Örnekleri", onBack: onBack)
                    NovaHelpHint(text: "56 düzenlenebilir Word örneği. Uygun formu arayın, indirin ve kendi saha prosedürünüze göre uyarlayın. Bu örnekler çalışma onayı veya izin kaydı oluşturmaz.")
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        TextField("Form, iş veya kelime ara", text: $query)
                            .accessibilityIdentifier("permit.search")
                    }
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 8) {
                        NovaFileChooserButton(label: "Sektör", value: sector ?? "Tüm sektörler",
                            isOpen: openFilter == "sector", identifier: "permit.sector") {
                            openFilter = openFilter == "sector" ? nil : "sector"
                        }
                        NovaFileChooserButton(label: "İş grubu", value: job ?? "Tüm işler",
                            isOpen: openFilter == "job", identifier: "permit.job") {
                            openFilter = openFilter == "job" ? nil : "job"
                        }
                    }
                    if let openFilter {
                        NovaFileChooserPanel(
                            options: openFilter == "sector"
                                ? [.init(id: nil, title: "Tüm sektörler")] + sectors.map { .init(id: $0, title: $0) }
                                : [.init(id: nil, title: "Tüm işler")] + jobs.map { .init(id: $0, title: $0) },
                            selected: openFilter == "sector" ? sector : job,
                            identifier: "permit.\(openFilter).options") { value in
                            if openFilter == "sector" { sector = value } else { job = value }
                            self.openFilter = nil
                        }
                    }
                    NovaText(text: "\(visible.count) / \(templates.count) örnek form", style: .metaQuiet)
                    if let exportError { NovaText(text: exportError, style: .metaQuiet) }
                    if templates.isEmpty {
                        NovaEmptyState(title: "Formlar yüklenemedi", message: "Uygulama paketindeki Word kataloğu bulunamadı.")
                    } else if visible.isEmpty {
                        NovaEmptyState(title: "Uygun form bulunamadı", message: "Arama kelimesini veya filtreleri değiştirin.")
                    } else {
                        ForEach(visible) { item in
                            NovaCard(padding: 12) {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        NovaText(text: "\(item.code) · \(item.title)", style: .bodyStrong)
                                            .lineLimit(2)
                                        NovaText(text: item.usage, style: .meta)
                                            .lineLimit(1)
                                        NovaText(text: item.jobs.joined(separator: " · "), style: .metaQuiet)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if let url = item.fileURL {
                                        Button { beginExport(item, url: url) } label: {
                                            Image(systemName: "arrow.down.to.line")
                                                .font(.system(size: 18, weight: .semibold))
                                                .frame(width: 44, height: 44)
                                                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(item.title) Word dosyasını indir")
                                        .accessibilityIdentifier("permit.download.\(item.code)")
                                    } else {
                                        Image(systemName: "exclamationmark.triangle")
                                            .accessibilityLabel("Word dosyası bulunamadı")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, novaTabBarInset)
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: NovaWorkPermitWordDocument.docxType,
                      defaultFilename: exportName) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
            exportDocument = nil
        }
    }

    private func beginExport(_ item: NovaWorkPermitTemplate, url: URL) {
        do {
            exportDocument = NovaWorkPermitWordDocument(data: try Data(contentsOf: url))
            exportName = String(item.filename.dropLast(".docx".count))
            exportError = nil
            exporting = true
        } catch {
            exportError = "Word dosyası açılamadı. Tekrar deneyin."
        }
    }
}
