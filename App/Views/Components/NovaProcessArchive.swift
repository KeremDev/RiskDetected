import SwiftUI

struct NovaProcessArchive: View {
    let identity: NovaSessionIdentity
    var onBack: () -> Void = {}

    struct Entry: Decodable, Identifiable {
        let id: UUID
        let version: Int
        let document_no: String
        let company_name: String
        let kind: String
        var key: String { "\(id):\(version)" }
    }

    private enum Section: String, CaseIterable, Identifiable {
        case process, analysis, nonconformity, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .process: return "Süreç belgeleri"
            case .analysis: return "Analiz raporları"
            case .nonconformity: return "Uygunsuzluk raporları"
            case .custom: return "Özel raporlarım"
            }
        }
    }

    @State private var section: Section = .process
    @State private var entries: [Entry] = []
    @State private var custom: [NovaGeneratedReport] = []
    @State private var busy = false
    @State private var failure: String?
    @State private var more = false
    @State private var file: URL?
    private var service: NovaProcessService { .init(identity: identity) }

    private var visibleEntries: [Entry] {
        switch section {
        case .nonconformity:
            return entries.filter { $0.kind.localizedCaseInsensitiveContains("nonconform") || $0.kind.localizedCaseInsensitiveContains("finding") }
        default:
            return entries.filter { !$0.kind.localizedCaseInsensitiveContains("nonconform") && !$0.kind.localizedCaseInsensitiveContains("finding") }
        }
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 12) {
                NovaPageHeading(title: "Rapor Arşivi", onBack: onBack).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Section.allCases) { item in
                            Button { section = item } label: {
                                NovaText(text: item.title, style: section == item ? .buttonSm : .meta)
                                    .padding(.horizontal, 12).frame(minHeight: 42)
                                    .background(section == item ? NovaColorToken.accent.color(in: .light)
                                        : NovaColorToken.surface.color(in: .light), in: Capsule())
                            }.buttonStyle(NovaRowPressStyle())
                        }
                    }.padding(.horizontal, 16)
                }
                content
            }
        }
        .task { await load(); custom = NovaGeneratedReportArchive.load() }
        .onChange(of: section) { _ in custom = NovaGeneratedReportArchive.load() }
        .sheet(item: $file) { NovaFileShareSheet(url: $0) }
    }

    @ViewBuilder private var content: some View {
        if section == .analysis {
            ReportView()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if busy { ProgressView("Yükleniyor…").frame(maxWidth: .infinity) }
                    if let failure {
                        NovaTaskErrorSummary(message: failure)
                        NovaButton(label: "Yeniden dene", symbol: "arrow.clockwise", variant: .surface) {
                            Task { await load() }
                        }
                    }
                    if section == .custom { customContent }
                    else { serverContent }
                }.padding(16).padding(.bottom, novaTabBarInset)
            }
        }
    }

    @ViewBuilder private var serverContent: some View {
        if visibleEntries.isEmpty && !busy && failure == nil {
            NovaEmptyState(title: section == .nonconformity ? "Henüz uygunsuzluk raporu yok" : "Henüz süreç belgesi yok",
                message: section == .nonconformity
                    ? "Uygunsuzluk raporları oluşturulduğunda firma ve sürüm bilgileriyle burada görünür."
                    : "Hazırladığınız süreç belgeleri ve önceki sürümleri burada görünür.")
        }
        ForEach(visibleEntries, id: \.key) { entry in
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: archiveTitle(entry), style: .cardTitle)
                    NovaText(text: entry.company_name, style: .meta)
                    NovaText(text: "\(entry.document_no) · Sürüm \(entry.version)", style: .metaQuiet)
                    HStack {
                        Button("PDF indir") { Task { await open(entry, excel: false) } }
                        Button("Excel indir") { Task { await open(entry, excel: true) } }
                    }.disabled(busy)
                }
            }
        }
        if more && section == .process {
            Button("Daha fazla") { Task { await load(append: true) } }.disabled(busy)
        }
    }

    @ViewBuilder private var customContent: some View {
        if custom.isEmpty {
            NovaEmptyState(title: "Henüz özel rapor yok",
                message: "Rapor Merkezi'nde oluşturduğunuz firma, eğitim, iş ve ziyaret raporları burada saklanır.")
        }
        ForEach(custom) { report in
            Button { file = NovaGeneratedReportArchive.url(for: report) } label: {
                NovaCard(padding: 14) {
                    HStack(spacing: 11) {
                        Image(systemName: report.format == "PDF" ? "doc.text" : "tablecells")
                        VStack(alignment: .leading, spacing: 3) {
                            NovaText(text: report.title, style: .bodyStrong)
                            NovaText(text: [report.companyName, report.period, report.format]
                                .compactMap { $0 }.joined(separator: " · "), style: .metaQuiet)
                        }
                        Spacer(); Image(systemName: "arrow.down.circle")
                    }.contentShape(Rectangle())
                }
            }.buttonStyle(NovaRowPressStyle())
        }
    }

    private func archiveTitle(_ entry: Entry) -> String {
        if entry.kind.localizedCaseInsensitiveContains("nonconform") || entry.kind.localizedCaseInsensitiveContains("finding") {
            return "Uygunsuzluk Raporu"
        }
        return NovaProcessKind.get(entry.kind).title
    }

    private func load(append: Bool = false) async {
        busy = true; failure = nil; defer { busy = false }
        do {
            let data = try await service.documents(offset: append ? entries.count : 0)
            let page = try JSONDecoder().decode([Entry].self, from: data)
            entries = append ? entries + page : page
            more = page.count == 20
        } catch { failure = NovaProcessService.message(error) }
    }

    private func open(_ entry: Entry, excel: Bool) async {
        busy = true; failure = nil; defer { busy = false }
        do {
            let snapshot = try JSONDecoder().decode(NovaProcessRow.self,
                from: await service.documents(document: entry.id, version: entry.version))
            file = try excel
                ? NovaProcessXLSX.write(snapshot, kind: .get(entry.kind), owner: identity.userID)
                : NovaProcessPDF.write(snapshot, kind: .get(entry.kind), owner: identity.userID)
        } catch { failure = NovaProcessService.message(error) }
    }
}
