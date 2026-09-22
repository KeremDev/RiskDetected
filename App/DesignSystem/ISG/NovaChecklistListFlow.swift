import SwiftUI

/// Templates are deliberately separated from completed field work. This page
/// owns only finding, inspecting, and managing reusable lists.
struct NovaChecklistListsScreen: View {
    let client: NovaChecklistClient
    var canWrite = true
    var initialCompany: UUID?
    let onBack: () -> Void
    let onStart: (String) -> Void

    private enum Section: String, CaseIterable, Identifiable {
        case ready, mine
        var id: String { rawValue }
        var title: String { self == .ready ? "Hazır listeler" : "Listelerim" }
    }

    @State private var section: Section = .ready
    @State private var library: NovaChecklistLibrary?
    @State private var templates: [NovaChecklistTemplate] = []
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var selectedCompany: UUID?
    @State private var search = ""
    @State private var sector: String?
    @State private var kind: String?
    @State private var showingFilters = false
    @State private var showingCreate = false
    @State private var detail: NovaChecklistTemplateDetail?
    @State private var editingTemplateCode: String?
    @State private var loading = true
    @State private var failure: String?
    @Environment(\.colorScheme) private var scheme

    private var hasCriteria: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sector != nil || kind != nil
    }
    private var activeFilterCount: Int { (sector == nil ? 0 : 1) + (kind == nil ? 0 : 1) }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    Picker("Liste bölümü", selection: $section) {
                        ForEach(Section.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("nova.checklist.lists.section")
                    if section == .ready { readyContent }
                    else { myListsContent }
                }
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 30)
            }
            .refreshable { await reload() }
        }
        .task { await initialLoad() }
        .task(id: search) {
            guard section == .ready else { return }
            do { try await Task.sleep(nanoseconds: 280_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            await loadLibrary(reset: true)
        }
        .onChange(of: section) { _ in Task { await reload() } }
        .sheet(isPresented: $showingFilters) {
            NovaChecklistLibraryFilterSheet(sectors: library?.sectors ?? [], sector: $sector, kind: $kind) {
                showingFilters = false
                Task { await loadLibrary(reset: true) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .novaFullScreenCover(isPresented: detailPresentation) {
            if let detail {
                NovaChecklistTemplateDetailScreen(template: detail, canWrite: canWrite,
                    companyName: companies.first { $0.id == selectedCompany }?.name,
                    onBack: { self.detail = nil },
                    onStart: {
                        self.detail = nil
                        onStart(detail.templateCode)
                    },
                    onCopy: { await copy(detail) },
                    onAssign: { await assign(detail) })
            }
        }
        .novaFullScreenCover(isPresented: $showingCreate) {
            NovaChecklistCreateListScreen(onBack: { showingCreate = false }) { title in
                await createList(title)
            }
        }
        .novaFullScreenCover(isPresented: editorPresentation) {
            if let code = editingTemplateCode {
                NovaChecklistMyListEditorScreen(client: client, company: selectedCompany,
                    templateCode: code, onBack: {
                        editingTemplateCode = nil
                        Task { await loadTemplates() }
                    })
            }
        }
    }

    private var header: some View {
        NovaListHeading(title: "Kontrol Listeleri", onBack: onBack) {
            if section == .mine && canWrite {
                NovaButton(label: "Yeni liste", symbol: "plus", compact: true) { showingCreate = true }
                    .accessibilityIdentifier("nova.checklist.template.create")
            }
        }
    }

    private var readyContent: some View {
        Group {
            NovaHelpHint(text: "Sektör, ekipman, faaliyet veya tehlikeye göre arayın; filtre düğmesiyle sonuçları daraltın.")
            HStack(spacing: 10) {
                NovaAnalysisSearchField(text: $search, placeholder: "Sektör, ekipman veya iş ara",
                    identifier: "nova.checklist.library.search")
                Button { showingFilters = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .background(NovaColorToken.surface.color(in: scheme),
                                in: RoundedRectangle(cornerRadius: 12))
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)").font(.system(size: 9, weight: .bold))
                                .frame(width: 17, height: 17)
                                .background(NovaColorToken.accent.color(in: scheme), in: Circle())
                                .padding(2)
                        }
                    }
                }
                .buttonStyle(NovaRowPressStyle())
                .accessibilityLabel(activeFilterCount == 0 ? "Filtre" : "Filtre, \(activeFilterCount) etkin")
            }
            if !hasCriteria {
                NovaChecklistMessageState(symbol: "magnifyingglass", title: "Bir liste bulun",
                    message: "Liste adına göre arayın veya sektör ve tür filtresi seçin.",
                    actionTitle: nil, action: {})
            } else if loading && library == nil {
                NovaChecklistRunSkeleton()
            } else if let failure {
                NovaChecklistMessageState(symbol: "wifi.exclamationmark", title: "Hazır listeler yüklenemedi",
                    message: failure, actionTitle: "Yeniden dene") { Task { await loadLibrary(reset: true) } }
            } else if let library, library.rows.isEmpty {
                NovaChecklistMessageState(symbol: "magnifyingglass", title: "Sonuç bulunamadı",
                    message: "Arama kelimenizi veya filtreleri değiştirin.",
                    actionTitle: activeFilterCount > 0 ? "Filtreleri temizle" : nil) {
                        sector = nil; kind = nil
                        Task { await loadLibrary(reset: true) }
                    }
            } else if let library {
                LazyVStack(spacing: 0) {
                    ForEach(library.rows) { item in
                        libraryRow(item)
                        Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                    }
                    if library.hasMore {
                        NovaButton(label: "Daha fazla göster", symbol: "chevron.down", variant: .surface) {
                            Task { await loadLibrary(reset: false) }
                        }
                        .padding(.top, 14)
                    }
                }
            }
        }
    }

    private var myListsContent: some View {
        Group {
            if loading && templates.isEmpty {
                NovaChecklistRunSkeleton()
            } else if let failure {
                NovaChecklistMessageState(symbol: "wifi.exclamationmark", title: "Listeleriniz yüklenemedi",
                    message: failure, actionTitle: "Yeniden dene") { Task { await loadTemplates() } }
            } else if templates.isEmpty {
                NovaChecklistMessageState(symbol: "list.bullet.rectangle", title: "Henüz listeniz yok",
                    message: "Yeni bir liste oluşturup hazır maddelerden seçebilir veya kendi sorularınızı yazabilirsiniz.",
                    actionTitle: nil, action: {})
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(templates) { template in
                        Button { editingTemplateCode = template.templateCode } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    NovaText(text: template.title, style: .bodyStrong)
                                    NovaText(text: templateSubtitle(template), style: .meta,
                                        color: NovaColorToken.textSecondary.color(in: scheme))
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                                    .frame(width: 32, height: 44)
                            }
                            .padding(.vertical, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(NovaRowPressStyle())
                        Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                    }
                }
            }
        }
    }

    private func libraryRow(_ item: NovaChecklistLibraryItem) -> some View {
        Button { Task { await openDetail(item.templateCode) } } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    NovaText(text: item.title, style: .bodyStrong)
                    NovaText(text: [item.sectorName, kindTitle(item.kind)]
                        .compactMap { $0 }.joined(separator: " · "), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    NovaText(text: "\(item.items) soru", style: .meta,
                        color: NovaColorToken.textMuted.color(in: scheme))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                    .frame(width: 32, height: 44)
            }
            .padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("nova.checklist.library.\(item.catalogTemplateCode)")
    }

    private var detailPresentation: Binding<Bool> {
        Binding(get: { detail != nil }, set: { if !$0 { detail = nil } })
    }
    private var editorPresentation: Binding<Bool> {
        Binding(get: { editingTemplateCode != nil }, set: { if !$0 { editingTemplateCode = nil } })
    }

    private func initialLoad() async {
        loading = true; failure = nil
        do {
            async let companyResult = client.companies()
            async let libraryResult = client.library("", nil, nil, 0)
            companies = try await companyResult
            selectedCompany = initialCompany
            library = try await libraryResult
            templates = try await client.templates(selectedCompany)
        } catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        loading = false
    }

    private func reload() async {
        if section == .ready { await loadLibrary(reset: true) }
        else { await loadTemplates() }
    }

    private func loadLibrary(reset: Bool) async {
        guard hasCriteria else { loading = false; failure = nil; return }
        let offset = reset ? 0 : (library?.offset ?? 0) + (library?.limit ?? 30)
        loading = true; failure = nil
        do {
            let value = try await client.library(search, sector, kind, offset)
            if reset || library == nil { library = value }
            else if let old = library {
                library = .init(catalogVersion: value.catalogVersion,
                    publicationStatus: value.publicationStatus,
                    professionalReviewStatus: value.professionalReviewStatus,
                    sectors: value.sectors, rows: old.rows + value.rows,
                    matchedItems: value.matchedItems, total: value.total,
                    limit: value.limit, offset: value.offset)
            }
        } catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        loading = false
    }

    private func loadTemplates() async {
        loading = true; failure = nil
        do { templates = try await client.templates(selectedCompany) }
        catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        loading = false
    }

    private func openDetail(_ code: String) async {
        failure = nil
        do { detail = try await client.templateDetail(code) }
        catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
    }

    private func createList(_ title: String) async -> String? {
        do {
            try await client.draftTemplate(selectedCompany, title)
            let values = try await client.templates(selectedCompany)
            templates = values
            guard let created = values.first(where: {
                $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else { return "Liste oluşturuldu ancak düzenleme ekranı açılamadı." }
            showingCreate = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                editingTemplateCode = created.templateCode
            }
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func copy(_ template: NovaChecklistTemplateDetail) async -> String? {
        do {
            try await client.copyTemplate(selectedCompany, template.templateCode, nil)
            await loadTemplates(); return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func assign(_ template: NovaChecklistTemplateDetail) async -> String? {
        guard let selectedCompany else { return "Listeyi firmaya atamak için Kontroller ekranından firma filtresi seçin." }
        do { try await client.assignTemplate(selectedCompany, nil, template.templateCode); return nil }
        catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func templateSubtitle(_ template: NovaChecklistTemplate) -> String {
        let version = template.draft ?? template.published ?? template.versions.first
        let state = version?.statusTitle ?? "Taslak"
        return "\(state) · \(version?.items.count ?? 0) soru"
    }

    private func kindTitle(_ value: String) -> String {
        switch value {
        case "sector": return "Sektör"
        case "activity": return "Faaliyet"
        case "equipment": return "Ekipman"
        case "hazard": return "Tehlike"
        default: return "Genel"
        }
    }
}

private struct NovaChecklistLibraryFilterSheet: View {
    let sectors: [NovaChecklistLibrarySector]
    @Binding var sector: String?
    @Binding var kind: String?
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let kinds = [("sector", "Sektör"), ("activity", "Faaliyet"),
        ("equipment", "Ekipman"), ("hazard", "Tehlike"), ("general", "Genel")]

    var body: some View {
        NavigationStack {
            List {
                Section("Tür") {
                    choice("Tümü", selected: kind == nil) { kind = nil }
                    ForEach(kinds, id: \.0) { value in
                        choice(value.1, selected: kind == value.0) { kind = value.0 }
                    }
                }
                Section("Sektör") {
                    choice("Tümü", selected: sector == nil) { sector = nil }
                    ForEach(sectors) { item in
                        choice("\(item.name) (\(item.count))", selected: sector == item.code) { sector = item.code }
                    }
                }
                if sector != nil || kind != nil {
                    Section { Button("Tüm filtreleri temizle") { sector = nil; kind = nil } }
                }
            }
            .navigationTitle("Filtre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Uygula") { onApply(); dismiss() } }
            }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark") } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NovaChecklistTemplateDetailScreen: View {
    let template: NovaChecklistTemplateDetail
    var canWrite = true
    let companyName: String?
    let onBack: () -> Void
    let onStart: () -> Void
    let onCopy: () async -> String?
    let onAssign: () async -> String?
    @State private var working = false
    @State private var failure: String?
    @State private var exportURL: URL?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NovaText(text: template.title, style: .screenTitle)
                        NovaText(text: [kindTitle, "\(template.items.count) soru"]
                            .compactMap { $0 }.joined(separator: " · "), style: .body,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        if let scope = template.scopeNote, !scope.isEmpty {
                            NovaText(text: scope, style: .body)
                        }
                        if template.professionalReviewStatus == "approved" {
                            Label("Uzmanlık alanı incelemesi tamamlandı", systemImage: "checkmark.seal")
                                .font(NovaFont.font(.meta))
                                .foregroundStyle(NovaColorToken.statusSuccessInk.color(in: scheme))
                        }
                        NovaText(text: "Sorular", style: .sectionTitle)
                        ForEach(template.items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                NovaText(text: "\(item.position).", style: .meta,
                                    color: NovaColorToken.textMuted.color(in: scheme))
                                NovaText(text: item.prompt, style: .body)
                            }
                            .padding(.vertical, 8)
                            Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                        }
                        if let failure {
                            NovaText(text: failure, style: .meta,
                                color: NovaColorToken.statusDangerInk.color(in: scheme))
                        }
                    }
                    .padding(20).padding(.bottom, canWrite ? 110 : 30)
                }
                if canWrite {
                    NovaButton(label: "Bu listeyle kontrol başlat", symbol: "play", variant: .primary,
                        isLoading: working, action: onStart)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(NovaColorToken.surface.color(in: scheme))
                }
            }
        }
        .sheet(item: $exportURL) { NovaFileShareSheet(url: $0) }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) { Label("Listeler", systemImage: "chevron.left").frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
            Spacer()
            Menu {
                Button("Boş PDF") { tryExportPDF() }
                Button("Boş Excel") { tryExportExcel() }
                if canWrite {
                    Button("Listelerime kopyala") { Task { await perform(onCopy) } }
                    Button("Firmaya ata") { Task { await perform(onAssign) } }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20)).frame(width: 44, height: 44)
            }
        }
        .overlay { NovaText(text: "Liste detayı", style: .label) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private var kindTitle: String? {
        switch template.kind {
        case "sector": return "Sektör"
        case "activity": return "Faaliyet"
        case "equipment": return "Ekipman"
        case "hazard": return "Tehlike"
        case .some: return "Genel"
        case nil: return nil
        }
    }

    private func perform(_ operation: () async -> String?) async {
        working = true; failure = await operation(); working = false
    }
    private func tryExportPDF() {
        do { exportURL = try NovaChecklistExport.pdf(template: template) }
        catch { failure = "PDF oluşturulamadı." }
    }
    private func tryExportExcel() {
        do { exportURL = try NovaChecklistExport.xlsx(template: template) }
        catch { failure = "Excel dosyası oluşturulamadı." }
    }
}

private struct NovaChecklistCreateListScreen: View {
    let onBack: () -> Void
    let onCreate: (String) async -> String?
    @State private var title = ""
    @State private var working = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) { Label("Listelerim", systemImage: "chevron.left").frame(minHeight: 44) }
                        .buttonStyle(NovaRowPressStyle())
                    Spacer()
                }
                .overlay { NovaText(text: "Yeni liste", style: .label) }
                .padding(.horizontal, 16).padding(.vertical, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NovaText(text: "Listenize bir ad verin", style: .screenTitle)
                        NovaText(text: "Sonraki ekranda hazır maddelerden seçim yapabilir veya kendi sorularınızı ekleyebilirsiniz.",
                            style: .body, color: NovaColorToken.textSecondary.color(in: scheme))
                        TextField("Liste adı", text: $title)
                            .font(NovaFont.font(.body)).padding(14)
                            .novaControlBackground(cornerRadius: 12).focused($focused)
                            .accessibilityIdentifier("nova.checklist.templates.name")
                        if let failure { NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                    }
                    .padding(20).padding(.bottom, 90)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NovaButton(label: working ? "Oluşturuluyor…" : "Listeyi oluştur", symbol: "plus",
                        variant: .primary, isEnabled: !cleanTitle.isEmpty, isLoading: working) {
                        Task {
                            working = true; failure = await onCreate(cleanTitle); working = false
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme))
                }
            }
        }
        .onAppear { focused = true }
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}
