import SwiftUI

/// Guided full-screen creation: scope, list, details. No long popup, no
/// redundant stepper, and only the final screen owns a primary action.
struct NovaChecklistStartFlowScreen: View {
    let client: NovaChecklistClient
    var initialCompany: UUID?
    var preselectedTemplate: String?
    let onStarted: (NovaChecklistRun) -> Void
    let onClose: () -> Void

    private enum Step { case scope, list, details, information }
    @State private var step: Step = .scope
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var company: UUID?
    @State private var catalogue: NovaChecklistCatalogue?
    @State private var selectedTemplate: String?
    @State private var templateDetail: NovaChecklistTemplateDetail?
    @State private var search = ""
    @State private var sector: String?
    @State private var kind: String?
    @State private var workplace: UUID?
    @State private var day = Date()
    @State private var area = ""
    @State private var equipment = ""
    @State private var document = ""
    @State private var showsSiteDetails = false
    @State private var loading = true
    @State private var working = false
    @State private var failure: String?
    @Environment(\.colorScheme) private var scheme

    private var selectedCompany: NovaAnalysisCompanyOption? { companies.first { $0.id == company } }
    private var selectedStarter: NovaChecklistStarter? {
        catalogue?.starters.first { $0.templateCode == selectedTemplate }
    }
    private var filteredStarters: [NovaChecklistStarter] {
        guard let starters = catalogue?.starters else { return [] }
        let needle = folded(search)
        let tokens = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        var seen = Set<String>()
        return starters.filter { item in
            guard sector == nil || item.sectorCode == sector else { return false }
            guard kind == nil || item.kind == kind else { return false }
            let text = folded([item.title, item.kindTitle, item.sectorCode, item.scopeNote]
                .compactMap { $0 }.joined(separator: " "))
            guard tokens.allSatisfy(text.contains) else { return false }
            // The catalogue keeps every published version in the background.
            // Selection shows one logical list so users do not see duplicates.
            return seen.insert(folded(item.title) + ":" + (item.kind ?? "general")).inserted
        }
    }
    private var sectors: [String] {
        Array(Set((catalogue?.starters ?? []).compactMap(\.sectorCode))).sorted()
    }
    private var kinds: [String] {
        Array(Set((catalogue?.starters ?? []).compactMap(\.kind))).sorted()
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: goBack) {
            Group {
                switch step {
                case .scope: scopePage
                case .list: listPage
                case .details: detailsPage
                case .information: informationPage
                }
            }
        }
        .task { await loadCompanies() }
    }

    private var scopePage: some View {
        VStack(spacing: 0) {
            header("Yeni kontrol", backTitle: "Vazgeç", back: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.start.flow.kontrol.nerede.yapilacak.05a798e3", table: .localizable, fallback: "Kontrol nerede yapılacak?"), style: .screenTitle)
                    if loading {
                        NovaChecklistRunSkeleton()
                    } else if let failure {
                        NovaChecklistMessageState(symbol: "wifi.exclamationmark",
                            title: RDLocalization.string("localizable.nova.checklist.start.flow.kontrol.kapsami.yuklenemedi.07fd930d", table: .localizable, fallback: "Kontrol kapsamı yüklenemedi"), message: failure,
                            actionTitle: "Yeniden dene") { Task { await loadCompanies() } }
                    } else {
                        if initialCompany == nil {
                            scopeRow(title: RDLocalization.string("localizable.nova.checklist.start.flow.bagimsiz.kontrol.36e5494f", table: .localizable, fallback: "Bağımsız kontrol"), subtitle: RDLocalization.string("localizable.nova.checklist.start.flow.firma.secmeden.kontrol.yapin.6b493058", table: .localizable, fallback: "Firma seçmeden kontrol yapın"),
                                symbol: "person.crop.square") { Task { await selectCompany(nil) } }
                            Divider()
                        }
                        ForEach(companies.filter { initialCompany == nil || $0.id == initialCompany }) { item in
                            scopeRow(title: item.name,
                                subtitle: item.detail.isEmpty ? "Firma kapsamında kontrol yapın" : item.detail,
                                symbol: "building.2") { Task { await selectCompany(item.id) } }
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 30)
            }
        }
    }

    private var listPage: some View {
        VStack(spacing: 0) {
            header("Kontrol listesini seç", backTitle: "Kapsam", back: { step = .scope })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: selectedCompany?.name ?? "Bağımsız kontrol", style: .label)
                            NovaText(text: RDLocalization.string("localizable.nova.checklist.start.flow.kontrol.kapsami.69fdc8a2", table: .localizable, fallback: "Kontrol kapsamı"), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer()
                        Button(RDLocalization.string("localizable.nova.checklist.start.flow.degistir.0607729b", table: .localizable, fallback: "Değiştir")) { step = .scope }.buttonStyle(NovaRowPressStyle())
                    }
                    .padding(.bottom, 18)

                    NovaHelpHint(text: RDLocalization.string("localizable.nova.checklist.start.flow.sektor.ekipman.faaliyet.veya.tehlikeye.gore.aray.969bfb6c", table: .localizable, fallback: "Sektör, ekipman, faaliyet veya tehlikeye göre arayın; yalnızca işinize uygun listeyi seçin."))
                        .padding(.bottom, 12)

                    NovaAnalysisSearchField(text: $search, placeholder: RDLocalization.string("localizable.nova.checklist.start.flow.sektor.ekipman.veya.is.ara.44e12788", table: .localizable, fallback: "Sektör, ekipman veya iş ara"),
                        identifier: "nova.checklist.start.search")
                        .padding(.bottom, 10)

                    HStack(spacing: 8) {
                        NovaFilterField(label: RDLocalization.string("localizable.nova.checklist.start.flow.sektor.53969f5c", table: .localizable, fallback: "Sektör"),
                            options: [.init(id: nil, title: RDLocalization.string("localizable.nova.checklist.start.flow.tum.sektorler.d14d0386", table: .localizable, fallback: "Tüm sektörler"))] + sectors.map {
                                .init(id: $0, title: sectorTitle($0))
                            }, selected: sector, identifier: "nova.checklist.start.sector") {
                                sector = $0
                            }
                        NovaFilterField(label: RDLocalization.string("localizable.nova.checklist.start.flow.liste.turu.0e9858ea", table: .localizable, fallback: "Liste türü"),
                            options: [.init(id: nil, title: RDLocalization.string("localizable.nova.checklist.start.flow.tum.turler.7e9303c9", table: .localizable, fallback: "Tüm türler"))] + kinds.map {
                                .init(id: $0, title: kindTitle($0) ?? "Genel")
                            }, selected: kind, identifier: "nova.checklist.start.kind") {
                                kind = $0
                            }
                    }
                    .padding(.bottom, 14)

                    if loading {
                        NovaChecklistRunSkeleton()
                    } else if let failure {
                        NovaChecklistMessageState(symbol: "wifi.exclamationmark",
                            title: RDLocalization.string("localizable.nova.checklist.start.flow.kontrol.listeleri.yuklenemedi.eb0476ce", table: .localizable, fallback: "Kontrol listeleri yüklenemedi"), message: failure,
                            actionTitle: "Yeniden dene") { Task { await loadCatalogue(company) } }
                    } else if filteredStarters.isEmpty {
                        NovaChecklistMessageState(symbol: "magnifyingglass", title: RDLocalization.string("localizable.nova.checklist.start.flow.liste.bulunamadi.ed8e052e", table: .localizable, fallback: "Liste bulunamadı"),
                            message: search.isEmpty
                                ? "Yayımlanmış bir kontrol listesi bulunmuyor."
                                : "Başka bir liste adı veya konu yazmayı deneyin.",
                            actionTitle: nil, action: {})
                    } else {
                        ForEach(filteredStarters) { starter in
                            starterRow(starter)
                            Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 30)
            }
        }
    }

    private var detailsPage: some View {
        VStack(spacing: 0) {
            header("Kontrol ayrıntıları", backTitle: "Liste seçimi", back: { step = .list })
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    detailRow("Firma", selectedCompany?.name ?? "Bağımsız kontrol")
                    detailRow("Liste", selectedStarter?.title ?? "—")
                    DatePicker("Kontrol tarihi", selection: $day, in: ...Date(), displayedComponents: .date)
                        .font(NovaFont.font(.body))
                    if let catalogue, company != nil, catalogue.workplaces.count > 1 {
                        workplaceField(catalogue)
                    } else if let catalogue, company != nil, let only = catalogue.workplaces.first {
                        detailRow("İşyeri", only.name)
                    }
                    DisclosureGroup(isExpanded: $showsSiteDetails) {
                        VStack(spacing: 12) {
                            input("Bölüm / alan", text: $area)
                            input("Makine / ekipman", text: $equipment)
                            input("Belge numarası", text: $document)
                        }
                        .padding(.top, 12)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            NovaText(text: RDLocalization.string("localizable.nova.checklist.start.flow.saha.ayrintilari.7928ccef", table: .localizable, fallback: "Saha ayrıntıları"), style: .label)
                            NovaText(text: [area, equipment, document].allSatisfy(\.isEmpty)
                                ? "İsteğe bağlı" : "Ayrıntılar eklendi", style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                    }
                    .padding(.vertical, 6)
                    if company == nil {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.start.flow.bagimsiz.kontrolde.firma.uygunsuzlugu.veya.firma.944bc7f2", table: .localizable, fallback: "Bağımsız kontrolde firma uygunsuzluğu veya firma kanıtı oluşturulmaz."),
                            style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .font(NovaFont.font(.meta))
                            .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                }
                .padding(20).padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaButton(label: working ? "Başlatılıyor…" : "Kontrolü başlat", symbol: "play",
                    variant: .primary, isEnabled: canStart, isLoading: working) { start() }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme))
            }
        }
    }

    private var informationPage: some View {
        VStack(spacing: 0) {
            header("Liste bilgileri", backTitle: "Liste seçimi", back: { step = .list })
            if loading {
                NovaChecklistRunSkeleton().padding(20)
            } else if let templateDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NovaText(text: templateDetail.title, style: .screenTitle)
                        NovaText(text: [kindTitle(templateDetail.kind), "\(templateDetail.items.count) soru"]
                            .compactMap { $0 }.joined(separator: " · "), style: .body,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        if let scope = templateDetail.scopeNote, !scope.isEmpty {
                            NovaText(text: scope, style: .body)
                        }
                        NovaText(text: "Sorular", style: .sectionTitle)
                        ForEach(templateDetail.items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                NovaText(text: "\(item.position).", style: .meta,
                                    color: NovaColorToken.textMuted.color(in: scheme))
                                NovaText(text: item.prompt, style: .body)
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                    .padding(20).padding(.bottom, 100)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NovaButton(label: RDLocalization.string("localizable.nova.checklist.start.flow.bu.listeyi.sec.7b4134ec", table: .localizable, fallback: "Bu listeyi seç"), symbol: "checkmark", variant: .primary) {
                        selectedTemplate = templateDetail.templateCode
                        step = .details
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme))
                }
            } else if let failure {
                NovaChecklistMessageState(symbol: "wifi.exclamationmark", title: RDLocalization.string("localizable.nova.checklist.start.flow.liste.yuklenemedi.edc55360", table: .localizable, fallback: "Liste yüklenemedi"),
                    message: failure, actionTitle: nil, action: {}).padding(20)
            }
        }
    }

    private func header(_ title: String, backTitle: String, back: @escaping () -> Void) -> some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    NovaText(text: backTitle, style: .buttonSm)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(NovaRowPressStyle())
            Spacer()
        }
        .overlay { NovaText(text: title, style: .label).lineLimit(1).padding(.horizontal, 100) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private func scopeRow(title: String, subtitle: String, symbol: String,
        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    NovaText(text: title, style: .cardTitle)
                    NovaText(text: subtitle, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            }
            .padding(.vertical, 15).contentShape(Rectangle())
        }
        .buttonStyle(NovaRowPressStyle())
    }

    private func starterRow(_ starter: NovaChecklistStarter) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedTemplate = starter.templateCode
                failure = nil
                step = .details
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    NovaText(text: starter.title, style: .bodyStrong)
                    NovaText(text: [starter.kindTitle, "\(starter.items) soru"]
                        .joined(separator: " · "), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(NovaRowPressStyle())
            Button { Task { await inspect(starter.templateCode) } } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .regular)).frame(width: 44, height: 44)
            }
            .buttonStyle(NovaRowPressStyle())
            .accessibilityLabel(RDLocalization.string("localizable.nova.checklist.start.flow.liste.bilgilerini.ac.68d1aad4", table: .localizable, fallback: "Liste bilgilerini aç"))
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: title, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
            NovaText(text: value, style: .bodyStrong)
        }
    }

    private func workplaceField(_ catalogue: NovaChecklistCatalogue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            NovaText(text: RDLocalization.string("localizable.nova.checklist.start.flow.isyeri.a1d04ce5", table: .localizable, fallback: "İşyeri"), style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
            Picker(RDLocalization.string("localizable.nova.checklist.start.flow.isyeri.eb2fcef7", table: .localizable, fallback: "İşyeri"), selection: $workplace) {
                Text(RDLocalization.string("localizable.nova.checklist.start.flow.isyeri.secin.2e94e039", table: .localizable, fallback: "İşyeri seçin")).tag(Optional<UUID>.none)
                ForEach(catalogue.workplaces) { item in Text(item.name).tag(Optional(item.id)) }
            }
            .pickerStyle(.menu)
            .padding(12).novaControlBackground(cornerRadius: 12)
        }
    }

    private func input(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(NovaFont.font(.body)).padding(13).novaControlBackground(cornerRadius: 12)
    }

    private var canStart: Bool {
        let requiresWorkplaceChoice = company != nil && (catalogue?.workplaces.count ?? 0) > 1
        return selectedTemplate != nil && (!requiresWorkplaceChoice || workplace != nil) && !working
    }

    private func loadCompanies() async {
        loading = true; failure = nil
        do {
            companies = try await client.companies()
            if let initialCompany {
                await selectCompany(initialCompany)
            }
        } catch {
            failure = "İnternet bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }

    private func selectCompany(_ id: UUID?) async {
        company = id
        await loadCatalogue(id)
        // A list handed over from Listelerim or the wizard goes straight to the
        // details; their back button still leads to the list page.
        let handedOver = preselectedTemplate != nil && selectedTemplate == preselectedTemplate
        if failure == nil { step = handedOver ? .details : .list }
    }

    private func loadCatalogue(_ id: UUID?) async {
        loading = true; failure = nil
        do {
            catalogue = try await client.catalogue(id)
            workplace = nil
            if id != nil, catalogue?.workplaces.count == 1 { workplace = catalogue?.workplaces.first?.id }
            if let preselectedTemplate,
               catalogue?.starters.contains(where: { $0.templateCode == preselectedTemplate }) == true {
                selectedTemplate = preselectedTemplate
            }
        } catch let error as NovaChecklistFailure {
            failure = error.message
        } catch {
            failure = "Kontrol listeleri yüklenemedi. Seçimi yeniden deneyin."
        }
        loading = false
    }

    private func inspect(_ code: String) async {
        loading = true; failure = nil; templateDetail = nil; step = .information
        do { templateDetail = try await client.templateDetail(code) }
        catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        loading = false
    }

    private func start() {
        guard let selectedTemplate, canStart else { return }
        Task {
            working = true; failure = nil
            do {
                guard let created = try await client.startRun(company, workplace, selectedTemplate,
                    NovaDayField.text(day), area, equipment, document) else {
                    throw NovaChecklistFailure.unavailable
                }
                onStarted((try? await client.detail(created.id)) ?? created)
            } catch let error as NovaChecklistFailure {
                failure = error.message
            } catch {
                failure = NovaChecklistFailure.unavailable.message
            }
            working = false
        }
    }

    private func goBack() {
        switch step {
        case .scope: onClose()
        case .list: step = .scope
        case .details, .information: step = .list
        }
    }

    private func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
    }

    private func kindTitle(_ value: String?) -> String? {
        switch value {
        case "sector": return RDLocalization.string("localizable.nova.checklist.start.flow.sektor.8c15ab52", table: .localizable, fallback: "Sektör")
        case "activity": return "Faaliyet"
        case "equipment": return "Ekipman"
        case "hazard": return "Tehlike"
        case .some: return RDLocalization.string("localizable.nova.checklist.start.flow.genel.6c810c6f", table: .localizable, fallback: "Genel")
        case nil: return nil
        }
    }

    private func sectorTitle(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }
}
