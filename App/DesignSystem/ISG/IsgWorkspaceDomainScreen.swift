import SwiftUI

extension IsgWorkspaceDomain {
    var title: String {
        switch self {
        case .personnel:
            return RDLocalization.string("localizable.nova.workspace.domain.personnel", table: .localizable,
                                         fallback: "Personel")
        case .training: return NovaDestination.training.title
        case .risk: return NovaDestination.riskAssessments.title
        case .nonconformity: return NovaDestination.findings.title
        case .checklist: return NovaDestination.checklists.title
        case .emergencyPlan: return NovaDestination.emergencyPlans.title
        case .drill: return NovaDestination.drills.title
        case .appointment: return NovaDestination.appointments.title
        case .ppe: return NovaDestination.ppeHandovers.title
        case .equipment: return NovaDestination.periodicChecks.title
        case .katip: return NovaDestination.katipContracts.title
        case .annualPlan: return NovaDestination.annualWorkPlans.title
        case .board: return NovaDestination.boardMeetings.title
        case .workPermit: return NovaDestination.workPermits.title
        case .visit: return NovaDestination.visits.title
        case .files: return NovaDestination.documents.title
        }
    }

    var symbol: String {
        switch self {
        case .personnel: return "person.2"
        case .training: return NovaDestination.training.symbol
        case .risk: return NovaDestination.riskAssessments.symbol
        case .nonconformity: return NovaDestination.findings.symbol
        case .checklist: return NovaDestination.checklists.symbol
        case .emergencyPlan: return NovaDestination.emergencyPlans.symbol
        case .drill: return NovaDestination.drills.symbol
        case .appointment: return NovaDestination.appointments.symbol
        case .ppe: return NovaDestination.ppeHandovers.symbol
        case .equipment: return NovaDestination.periodicChecks.symbol
        case .katip: return NovaDestination.katipContracts.symbol
        case .annualPlan: return NovaDestination.annualWorkPlans.symbol
        case .board: return NovaDestination.boardMeetings.symbol
        case .workPermit: return NovaDestination.workPermits.symbol
        case .visit: return NovaDestination.visits.symbol
        case .files: return NovaDestination.documents.symbol
        }
    }
}

/// A workspace-only operational browser. It is intentionally independent of
/// every personal service so an OSGB route cannot accidentally read data via
/// the legacy account owner boundary.
struct IsgWorkspaceDomainScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    let companyName: String
    let canOperate: Bool
    let onBack: () -> Void
    @State private var snapshot: IsgWorkspaceDomainSnapshot?
    @State private var selected: IsgWorkspaceDomainRecord?
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()
    @State private var showingCreate = false

    private var rows: [IsgWorkspaceDomainRecord] {
        let source = snapshot?.rows ?? []
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return source }
        return source.filter { row in
            ([row.title, row.subtitle, row.status].compactMap { $0 } + row.facts.map(\.1))
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: domain.title, onBack: onBack)
                    NovaHelpHint(text: String(format: RDLocalization.string(
                        "localizable.nova.workspace.domain.scope", table: .localizable,
                        fallback: "%@ firmasına ait yetkili OSGB kayıtları gösteriliyor."), companyName))
                    if let snapshot, !snapshot.metrics.isEmpty { metrics(snapshot.metrics) }
                    search
                    if canOperate {
                        NovaCompactActionButton(title: String(format: RDLocalization.string(
                            "localizable.nova.workspace.domain.add", table: .localizable,
                            fallback: "%@ ekle"), domain.title), symbol: "plus", prominent: true) {
                            showingCreate = true
                        }
                    }
                    if loading {
                        NovaLoadingView(message: RDLocalization.string(
                            "localizable.nova.workspace.domain.loading", table: .localizable,
                            fallback: "Kayıtlar yükleniyor…"))
                    } else if let error {
                        NovaEmptyState(title: RDLocalization.string(
                                "localizable.nova.workspace.domain.failed", table: .localizable,
                                fallback: "Kayıtlar yüklenemedi"), message: error)
                        NovaCompactActionButton(title: RDLocalization.string(
                                "localizable.nova.workspace.domain.retry", table: .localizable,
                                fallback: "Tekrar dene"), symbol: "arrow.clockwise") { revision = UUID() }
                    } else if rows.isEmpty {
                        NovaEmptyState(title: String(format: RDLocalization.string(
                                "localizable.nova.workspace.domain.empty", table: .localizable,
                                fallback: "Henüz %@ kaydı yok."), domain.title),
                            message: RDLocalization.string(
                                "localizable.nova.workspace.domain.empty.detail", table: .localizable,
                                fallback: "Yeni kayıtlar bu firmaya ve yetkili çalışma alanına bağlı olarak burada görünür."))
                    } else {
                        ForEach(rows) { row in record(row) }
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: revision) { await load() }
        .novaPopup(item: $selected) { row in
            IsgWorkspaceDomainDetail(store: store, domain: domain, row: row,
                                     canOperate: canOperate) {
                selected = nil
                revision = UUID()
            }
        }
        .novaPopup(isPresented: $showingCreate, onDismiss: { revision = UUID() }) {
            createEditor
        }
    }

    @ViewBuilder private var createEditor: some View {
        if domain == .files {
            IsgWorkspaceFileCreateEditor(store: store) { showingCreate = false }
        } else {
            IsgWorkspaceDomainCreateEditor(store: store, domain: domain) { showingCreate = false }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField(RDLocalization.string("localizable.nova.workspace.domain.search", table: .localizable,
                fallback: "Kayıtlarda ara"), text: $query)
                .font(NovaFont.font(.body)).submitLabel(.done)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle").frame(width: 36, height: 36) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RDLocalization.string(
                        "localizable.nova.nonconformity.search.clear", table: .localizable,
                        fallback: "Aramayı temizle"))
            }
        }.padding(.horizontal, 12).frame(minHeight: 48).novaControlBackground(cornerRadius: 16)
    }

    private func metrics(_ values: [IsgWorkspaceDomainMetric]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values) { metric in
                    NovaListStat(title: metricTitle(metric.id), symbol: metricSymbol(metric.id),
                                 value: String(metric.value)).frame(width: 112)
                }
            }
        }
    }

    private func record(_ row: IsgWorkspaceDomainRecord) -> some View {
        Button { selected = row } label: {
            NovaCard(padding: 14) {
                HStack(alignment: .top, spacing: 10) {
                    NovaIcon(symbol: domain.symbol, size: 19)
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: row.title, style: .bodyStrong)
                        if let subtitle = row.subtitle { NovaText(text: subtitle, style: .metaQuiet) }
                        if let status = row.status {
                            NovaStatusPill(label: statusLabel(status), status: statusTone(status))
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }.contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    @MainActor private func load() async {
        loading = true; error = nil
        do { snapshot = try await store.domain(domain) }
        catch {
            snapshot = nil
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                                               fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        loading = false
    }

    private func metricTitle(_ key: String) -> String {
        let last = key.split(separator: ".").last.map(String.init) ?? key
        let known: [String: String] = [
            "active": RDLocalization.string("localizable.nova.workspace.metric.active", table: .localizable, fallback: "Aktif"),
            "archived": RDLocalization.string("localizable.nova.workspace.metric.archived", table: .localizable, fallback: "Arşiv"),
            "total": RDLocalization.string("localizable.nova.workspace.metric.total", table: .localizable, fallback: "Toplam"),
            "planned": RDLocalization.string("localizable.nova.workspace.metric.planned", table: .localizable, fallback: "Planlı"),
            "completed": RDLocalization.string("localizable.nova.workspace.metric.completed", table: .localizable, fallback: "Tamamlanan"),
            "overdue": RDLocalization.string("localizable.nova.workspace.metric.overdue", table: .localizable, fallback: "Süresi geçen"),
            "open": RDLocalization.string("localizable.nova.workspace.metric.open", table: .localizable, fallback: "Açık")
        ]
        return known[last] ?? last.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func metricSymbol(_ key: String) -> String {
        if key.contains("overdue") || key.contains("expired") { return "exclamationmark.triangle" }
        if key.contains("completed") || key.contains("valid") { return "checkmark.circle" }
        if key.contains("people") || key.contains("employee") { return "person.2" }
        if key.contains("minute") { return "clock" }
        return domain.symbol
    }

    private func statusLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusTone(_ value: String) -> NovaStatus {
        switch value {
        case "closed", "completed", "performed", "valid", "active": return .success
        case "overdue", "expired", "failed", "critical": return .danger
        case "due_soon", "planned", "draft", "open": return .warning
        default: return .neutral
        }
    }
}

private struct IsgWorkspaceDomainDetail: View {
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    let row: IsgWorkspaceDomainRecord
    let canOperate: Bool
    let onChanged: () -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var preview: IsgWorkspaceDownloadedFile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    NovaIcon(symbol: domain.symbol, size: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: row.title, style: .sectionTitle)
                        if let subtitle = row.subtitle { NovaText(text: subtitle, style: .metaQuiet) }
                    }
                }
                if let status = row.status { NovaStatusPill(label: status, status: .neutral) }
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(row.facts.enumerated()), id: \.offset) { _, fact in
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: fact.0.replacingOccurrences(of: "_", with: " ").capitalized,
                                         style: .metaQuiet)
                                NovaText(text: fact.1, style: .bodyStrong)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if domain == .files {
                    NovaCompactActionButton(title: busy ? RDLocalization.string(
                        "localizable.nova.workspace.file.downloading", table: .localizable,
                        fallback: "Dosya hazırlanıyor…") : RDLocalization.string(
                            "localizable.nova.workspace.file.open", table: .localizable,
                            fallback: "Dosyayı aç"), symbol: "arrow.down.doc", prominent: true,
                        enabled: !busy && row.assetID != nil) { openFile() }
                    if canOperate {
                        NovaCompactActionButton(title: RDLocalization.string(
                            "localizable.nova.workspace.file.archive", table: .localizable,
                            fallback: "Arşivle"), symbol: "archivebox", enabled: !busy) { archive() }
                    }
                }
                if let error { NovaHelpHint(text: error) }
            }.padding(18).novaPopupContentSize()
        }
        .fullScreenCover(item: $preview) { DocumentPreview(url: $0.url) }
    }

    private func openFile() {
        guard !busy else { return }
        busy = true; error = nil
        Task { @MainActor in
            do {
                let download = try await store.downloadFile(row)
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("workspace-files-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let safeName = URL(fileURLWithPath: download.filename).lastPathComponent
                let url = folder.appendingPathComponent(safeName.isEmpty ? "belge" : safeName)
                try download.data.write(to: url, options: .atomic)
                preview = .init(url: url)
            } catch {
                self.error = RDLocalization.string(
                    "localizable.nova.workspace.file.download.failed", table: .localizable,
                    fallback: "Dosya açılamadı. Yetkinizi ve bağlantınızı kontrol edip yeniden deneyin.")
            }
            busy = false
        }
    }

    private func archive() {
        guard !busy else { return }
        busy = true; error = nil
        Task { @MainActor in
            do {
                try await store.archiveFile(row)
                onChanged()
            } catch {
                self.error = RDLocalization.string(
                    "localizable.nova.workspace.file.archive.failed", table: .localizable,
                    fallback: "Dosya arşivlenemedi. Sayfayı yenileyip yeniden deneyin.")
            }
            busy = false
        }
    }
}

private struct IsgWorkspaceDownloadedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct IsgWorkspaceChangeScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let companyName: String?
    let onBack: () -> Void
    @State private var rows: [IsgWorkspaceChange]?
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: NovaDestination.notifications.title, onBack: onBack)
                    if let companyName {
                        NovaHelpHint(text: String(format: RDLocalization.string(
                            "localizable.nova.workspace.change.scope", table: .localizable,
                            fallback: "%@ firmasındaki yetkili değişiklikler gösteriliyor."), companyName))
                    }
                    if loading {
                        NovaLoadingView(message: RDLocalization.string(
                            "localizable.nova.workspace.change.loading", table: .localizable,
                            fallback: "Değişiklikler yükleniyor…"))
                    } else if let error {
                        NovaEmptyState(title: RDLocalization.string(
                                "localizable.nova.workspace.change.failed", table: .localizable,
                                fallback: "Değişiklikler yüklenemedi"), message: error)
                    } else if (rows ?? []).isEmpty {
                        NovaEmptyState(title: RDLocalization.string(
                                "localizable.nova.workspace.change.empty", table: .localizable,
                                fallback: "Henüz değişiklik yok"),
                            message: RDLocalization.string(
                                "localizable.nova.workspace.change.empty.detail", table: .localizable,
                                fallback: "Bu çalışma alanındaki kayıt hareketleri burada görünür."))
                    } else {
                        ForEach(rows ?? [], id: \.sequence) { row in
                            NovaCard(padding: 12) {
                                HStack(spacing: 10) {
                                    NovaIcon(symbol: "arrow.triangle.2.circlepath", size: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        NovaText(text: row.aggregateType.replacingOccurrences(of: "_", with: " ").capitalized,
                                                 style: .bodyStrong)
                                        NovaText(text: row.eventType.replacingOccurrences(of: "_", with: " ").capitalized,
                                                 style: .metaQuiet)
                                    }
                                    Spacer(minLength: 0)
                                    NovaText(text: "#\(row.sequence)", style: .metaQuiet)
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
            .refreshable { revision = UUID() }
        }
        .task(id: revision) { await load() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { return }
                await load(showLoading: false)
            }
        }
    }

    @MainActor private func load(showLoading: Bool = true) async {
        if showLoading { loading = true }
        error = nil
        do { rows = try await store.changes(limit: 100).rows }
        catch {
            rows = nil
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                                               fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        if showLoading { loading = false }
    }
}
