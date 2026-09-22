import SwiftUI

private enum HistoryFilterChip: String, CaseIterable, Identifiable {
    case all
    case critical
    case unassigned
    case unreviewed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return RDLocalization.string(
                "localizable.history.filter.all",
                fallback: "Tümü"
            )
        case .critical:
            return RDLocalization.string(
                "localizable.history.filter.critical",
                fallback: "Kritik"
            )
        case .unassigned: return "Firmasız"
        case .unreviewed: return "İncelenmemiş"
        }
    }
}

private enum HistorySort: String, CaseIterable, Identifiable {
    case newest, highestRisk, mostFindings, unreviewed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "En yeni"
        case .highestRisk: return "En yüksek risk"
        case .mostFindings: return "En çok bulgu"
        case .unreviewed: return "İncelenmemiş önce"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var search: String = ""
    @State private var activeChip: HistoryFilterChip = .all
    @State private var sort: HistorySort = .newest
    @State private var showFilter: Bool = false
    @State private var showCompanyFilter: Bool = false
    @State private var companies: [Company] = []
    @State private var selectedCompanyFilter: Company?
    @State private var items: [HistoryItem] = []
    @State private var analysisResult: AnalysisResultBundle? = nil
    @State private var showResult = false
    @State private var analysisError: String? = nil
    @State private var isLoadingItems = false
    @State private var loadErrorMessage: String?
    @State private var openingItemID: UUID? = nil
    @State private var deletingItemID: UUID? = nil
    @State private var itemPendingDelete: HistoryItem?
    @State private var showPaywall = false

    private let chips = HistoryFilterChip.allCases
    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RDHeaderLogoButton(size: 18)
                    Spacer()
                    RDHeaderAccountCTA(
                        directEntryPoint: .analysesHeaderUpgrade,
                        menuEntryPoint: .analysesHeaderProfileMenuUpgrade
                    ) {
                        showPaywall = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .zIndex(100)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 9) {
                    analysisOverview
                    filterSurface

                    if isLoadingItems && items.isEmpty {
                        loadingState
                    } else if let loadErrorMessage, items.isEmpty {
                        loadErrorState(loadErrorMessage)
                    } else if filteredItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredItems) { item in
                            HistoryRow(
                                item: item,
                                companyName: companyName(for: item.companyID),
                                isLoading: openingItemID == item.id,
                                isDeleting: deletingItemID == item.id
                            ) {
                                openAnalysis(item)
                            } onDelete: {
                                itemPendingDelete = item
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Color.rdPaper)
        .task {
            await loadItems()
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task { await loadItems() }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet { showFilter = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showCompanyFilter) {
            CompanyPickerSheet(
                title: RDLocalization.string("localizable.history.view.analiz.firma.filtresi.c17b8b6a", table: .localizable, fallback: "Analiz firma filtresi"),
                accessTier: app.currentTier,
                selectedCompanyID: selectedCompanyFilter?.id,
                allowNoCompany: true,
                onSelect: { company in
                    selectedCompanyFilter = company
                },
                onPaywall: {
                    PaywallEventService.shared.beginEntry(
                        at: .analysesCompanyPicker,
                        currentTier: app.currentTier,
                        targetTier: .plus
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showPaywall = true
                    }
                }
            )
            .presentationDetents(CompanyPickerSheet.presentationDetents(for: app.currentTier))
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showResult) {
            ResultView(
                bundle: analysisResult,
                onClose: {
                    showResult = false
                    analysisResult = nil
                    Task { await loadItems() }
                }
            )
            .environmentObject(app)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .confirmationDialog(
            RDLocalization.string("localizable.history.view.analiz.silinsin.mi.61ba421c", table: .localizable, fallback: "Analiz silinsin mi?"),
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { if !$0 { itemPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(RDLocalization.string("localizable.history.view.analizi.sil.24e7f3a8", table: .localizable, fallback: "Analizi sil"), role: .destructive) {
                if let item = itemPendingDelete {
                    deleteAnalysis(item)
                }
            }
            Button(RDLocalization.string("localizable.history.view.vazgec.de467c3e", table: .localizable, fallback: "Vazgeç"), role: .cancel) {
                itemPendingDelete = nil
            }
        } message: {
            Text(RDLocalization.string("localizable.history.view.analiz.bulgular.fotograf.kaydi.ve.bu.analize.bag.dac9fca8", table: .localizable, fallback: "Analiz, bulgular, fotoğraf kaydı ve bu analize bağlı rapor kayıtları silinir."))
        }
        .alert(RDLocalization.string("localizable.history.view.analiz.hatasi.9e450a8a", table: .localizable, fallback: "Analiz Hatası"), isPresented: .init(
            get: { analysisError != nil },
            set: { if !$0 { analysisError = nil } }
        )) {
            Button(RDLocalization.string("localizable.history.view.tamam.8202ad1f", table: .localizable, fallback: "Tamam")) { analysisError = nil }
        } message: {
            Text(analysisError ?? "")
        }
    }

    private var analysisOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analizler")
                .font(RDTypography.font(size: RDFontScale.size(28), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
            HStack(spacing: 0) {
                overviewMetric(icon: "viewfinder", title: "Analiz", value: "\(items.count)")
                Rectangle().fill(Color.rdLine).frame(width: 1, height: 28)
                overviewMetric(icon: "exclamationmark.triangle.fill", title: "Kritik", value: "\(criticalCount)")
                Rectangle().fill(Color.rdLine).frame(width: 1, height: 28)
                overviewMetric(icon: "list.bullet", title: "Bulgu", value: "\(findingTotal)")
            }
            .frame(minHeight: 50)
            .background(Color.rdWhite)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.rdLine, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func overviewMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .foregroundStyle(title == "Kritik" ? Color.rdCriticalText : Color.rdSlate)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .rdMono(size: 16, weight: .bold)
                    .foregroundStyle(title == "Kritik" ? Color.rdCriticalText : Color.rdBlack)
                    .lineLimit(1)
                Text(title)
                    .font(RDTypography.font(size: RDFontScale.size(10), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private var overviewCardGradientColors: [Color] {
        colorScheme == .dark
            ? [Color(hex: "#151A18"), Color(hex: "#111615"), Color(hex: "#0F1D14")]
            : [Color(hex: "#F7FBFF"), Color(hex: "#F2F7FA"), Color(hex: "#EEF8F2")]
    }

    private var overviewCardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.rdOnyx
    }

    private var overviewMetricBackground: Color {
        colorScheme == .dark ? Color(hex: "#0B120F") : Color.rdOnyx
    }

    private var overviewMetricBorder: Color {
        colorScheme == .dark ? Color.rdGreen.opacity(0.20) : Color.rdOnyx
    }

    private var filterSurface: some View {
        VStack(spacing: 10) {
            searchField
            HStack(spacing: 8) {
                filterButton
                if app.currentTier.isPaid {
                    companyFilterButton
                }
                sortButton
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { c in
                        filterChip(c)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func filterChip(_ chip: HistoryFilterChip) -> some View {
        let active = chip == activeChip
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            activeChip = chip
        } label: {
            HStack(spacing: 6) {
                if active {
                    Image(systemName: "checkmark")
                        .font(RDTypography.font(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                }
                Text(chip.title)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(active ? .white : Color.rdCharcoal)
            .background(
                Capsule()
                    .fill(active ? Color.rdSelected : Color.rdFog)
            )
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(RDTypography.font(size: RDFontScale.size(14), weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            TextField(RDLocalization.string("localizable.history.view.analiz.ara.39912a48", table: .localizable, fallback: "Analiz ara"), text: $search)
                .font(RDTypography.font(size: RDFontScale.size(14), design: .rounded))
                .foregroundStyle(Color.rdBlack)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.rdCloud)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var filterButton: some View {
        Menu {
            ForEach(HistoryFilterChip.allCases) { option in
                Button { activeChip = option } label: {
                    if activeChip == option { Label(option.title, systemImage: "checkmark") }
                    else { Text(option.title) }
                }
            }
        } label: {
            compactFilterLabel(symbol: "line.3.horizontal.decrease",
                title: activeChip == .all ? "Filtre" : "Filtre · 1", active: activeChip != .all)
        }
        .accessibilityIdentifier("analysis.filter")
    }

    private var sortButton: some View {
        Menu {
            ForEach(HistorySort.allCases) { option in
                Button { sort = option } label: {
                    if sort == option { Label(option.title, systemImage: "checkmark") }
                    else { Text(option.title) }
                }
            }
        } label: {
            compactFilterLabel(symbol: "arrow.up.arrow.down", title: sort.title, active: false)
        }
        .accessibilityIdentifier("analysis.sort")
    }

    private func compactFilterLabel(symbol: String, title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(RDTypography.font(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
            Text(title).font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
            Image(systemName: "chevron.down").font(RDTypography.font(size: RDFontScale.size(8), weight: .bold, design: .rounded))
        }
        .foregroundStyle(active ? Color.rdGreenDark : Color.rdBlack)
        .padding(.horizontal, 11).frame(height: 38)
        .background(active ? Color.rdGreenSoft : Color.rdWhite)
        .overlay(Capsule().stroke(active ? Color.rdGreen : Color.rdLine, lineWidth: 1))
        .clipShape(Capsule())
    }

    private var companyFilterButton: some View {
        Button {
            showCompanyFilter = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: selectedCompanyFilter == nil ? "building.2" : "building.2.fill")
                .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                .frame(width: 40, height: 40)
                .foregroundStyle(selectedCompanyFilter == nil ? Color.rdBlack : Color.rdGreenDark)
                .background(selectedCompanyFilter == nil ? Color.rdCloud : Color.rdGreenSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedCompanyFilter == nil ? Color.rdLine : Color.rdGreen.opacity(0.32), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(RDLocalization.string("localizable.history.view.firma.filtresi.d774867d", table: .localizable, fallback: "Firma filtresi"))
        .accessibilityIdentifier("analysis.company_filter")
    }

    private var filteredItems: [HistoryItem] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = items.filter { item in
            let companyName = companyName(for: item.companyID).lowercased(with: .autoupdatingCurrent)
            let matchesSearch = needle.isEmpty
                || item.title.lowercased().contains(needle)
                || item.kind.lowercased().contains(needle)
                || companyName.contains(needle)
            let matchesCompany = selectedCompanyFilter == nil || item.companyID == selectedCompanyFilter?.id

            let matchesChip: Bool
            switch activeChip {
            case .critical:
                matchesChip = item.level == .critical
            case .unassigned:
                matchesChip = item.companyID == nil
            case .unreviewed:
                matchesChip = item.status != .reviewed
            case .all:
                matchesChip = true
            }

            return matchesSearch && matchesChip && matchesCompany
        }
        return filtered.sorted { left, right in
            switch sort {
            case .newest:
                return (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
            case .highestRisk:
                let leftRank = riskRank(left.level)
                let rightRank = riskRank(right.level)
                return leftRank == rightRank
                    ? (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
                    : leftRank > rightRank
            case .mostFindings:
                return left.count == right.count
                    ? (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
                    : left.count > right.count
            case .unreviewed:
                return left.status == right.status
                    ? (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
                    : left.status != .reviewed
            }
        }
    }

    private func riskRank(_ level: RiskLevel) -> Int {
        switch level {
        case .critical: return 4
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .unknown: return 0
        }
    }

    private var emptyState: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(RDTypography.font(size: RDFontScale.size(24), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 48, height: 48)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(RDLocalization.string("localizable.history.view.analiz.bulunamadi.e46caef9", table: .localizable, fallback: "Analiz bulunamadı"))
                    .font(RDTypography.font(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(RDLocalization.string("localizable.history.view.filtreyi.degistir.veya.yeni.bir.saha.taramasi.ba.e4cd2cb3", table: .localizable, fallback: "Filtreyi değiştir veya yeni bir saha taraması başlat."))
                    .font(RDTypography.font(size: RDFontScale.size(13), design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loadingState: some View {
        RDCard {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text(RDLocalization.string("localizable.history.view.analizler.yukleniyor.45550383", table: .localizable, fallback: "Analizler yükleniyor"))
                        .font(RDTypography.font(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("localizable.history.view.son.saha.taramalarin.getiriliyor.9dc0947a", table: .localizable, fallback: "Son saha taramaların getiriliyor."))
                        .font(RDTypography.font(size: RDFontScale.size(13), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func loadErrorState(_ message: String) -> some View {
        RDCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(RDTypography.font(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdCriticalText)
                    .frame(width: 48, height: 48)
                    .background(Color.rdCriticalBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(RDLocalization.string("localizable.history.view.analizler.yuklenemedi.c6417635", table: .localizable, fallback: "Analizler yüklenemedi"))
                        .font(RDTypography.font(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(message)
                        .font(RDTypography.font(size: RDFontScale.size(13), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await loadItems() }
                } label: {
                    Label(RDLocalization.string("localizable.history.view.tekrar.dene.0c468462", table: .localizable, fallback: "Tekrar dene"), systemImage: "arrow.clockwise")
                        .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.rdGreenDark)
                .accessibilityIdentifier("history.reload")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var criticalCount: Int {
        items.filter { $0.level == .critical }.count
    }

    private var weekCount: Int {
        items.filter { isThisWeek($0.createdAt) }.count
    }

    private var findingTotal: Int {
        items.reduce(0) { $0 + $1.count }
    }

    private func loadItems() async {
        guard app.auth.session != nil else { return }
        isLoadingItems = true
        defer { isLoadingItems = false }

        do {
            async let rowsTask = AnalysisService.shared.listRecent(limit: 50)
            async let companiesTask: [Company] = app.currentTier.isPaid
                ? CompanyService.shared.listCompanies(includeArchived: true)
                : []
            let rows = try await rowsTask
            let paths = try await AnalysisService.shared.firstPhotoPaths(analysisIDs: rows.map(\.id))
            companies = (try? await companiesTask) ?? []
            items = rows.map { row in
                HistoryItem(row: row, photoPath: paths[row.id])
            }
            loadErrorMessage = nil
        } catch {
            let message = AppErrorMessage.make(error, context: RDLocalization.string("localizable.history.view.analizler.yuklenemedi.da2ab2d1", table: .localizable, fallback: "Analizler yüklenemedi"), fallbackTitle: RDLocalization.string("localizable.history.view.analizler.yuklenemedi.da2ab2d1", table: .localizable, fallback: "Analizler yüklenemedi")).fullText
            loadErrorMessage = message
            if !items.isEmpty {
                analysisError = message
            }
        }
    }

    private func openAnalysis(_ item: HistoryItem) {
        guard openingItemID == nil else { return }
        openingItemID = item.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                analysisResult = try await AnalysisService.shared.result(analysisID: item.id)
                showResult = true
            } catch {
                analysisError = AppErrorMessage.make(error, context: RDLocalization.string("localizable.history.view.analiz.acilamadi.cc5dbdef", table: .localizable, fallback: "Analiz açılamadı"), fallbackTitle: RDLocalization.string("localizable.history.view.analiz.acilamadi.cc5dbdef", table: .localizable, fallback: "Analiz açılamadı")).fullText
            }
            openingItemID = nil
        }
    }

    private func deleteAnalysis(_ item: HistoryItem) {
        guard deletingItemID == nil else { return }
        itemPendingDelete = nil
        deletingItemID = item.id
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()

        Task {
            do {
                try await AnalysisService.shared.deleteAnalysis(
                    analysisID: item.id,
                    requestID: requestID,
                    supportID: supportID
                )
                items.removeAll { $0.id == item.id }
                if analysisResult?.analysis.id == item.id {
                    analysisResult = nil
                    showResult = false
                }
            } catch {
                analysisError = AppErrorMessage.make(
                    rawMessage: RDLocalization.format("localizable.history.view.1.destek.kodu.2.d09ac0f4", table: .localizable, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: error.localizedDescription), String(describing: supportID)]),
                    context: RDLocalization.string("localizable.history.view.analiz.silinemedi.c4654604", table: .localizable, fallback: "Analiz silinemedi"),
                    fallbackTitle: RDLocalization.string("localizable.history.view.analiz.silinemedi.c6ad3406", table: .localizable, fallback: "Analiz silinemedi")
                ).fullText
            }
            deletingItemID = nil
        }
    }

    private func isThisWeek(_ date: Date?) -> Bool {
        guard let date else { return false }
        let recentWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return date >= recentWeekStart
    }

    private func companyName(for companyID: UUID?) -> String {
        guard let companyID,
              let company = companies.first(where: { $0.id == companyID })
        else { return "" }
        return company.name
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let item: HistoryItem
    let companyName: String
    var isLoading: Bool = false
    var isDeleting: Bool = false
    let action: () -> Void
    let onDelete: () -> Void

    var body: some View {
        rowContent
            .contextMenu {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(RDLocalization.string("localizable.history.view.analizi.sil.2c80616e", table: .localizable, fallback: "Analizi sil"), systemImage: "trash")
                }
            }
            .accessibilityAction(named: RDLocalization.string("localizable.history.view.analizi.sil.93bad064", table: .localizable, fallback: "Analizi sil")) {
                onDelete()
            }
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                AnalysisThumbnail(path: item.photoPath, isTextAnalysis: item.isTextAnalysis, cornerRadius: 11)
                    .frame(width: 46, height: 46)

                Image(systemName: item.isTextAnalysis ? "text.alignleft" : "camera.fill")
                    .font(RDTypography.font(size: RDFontScale.size(8.5), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 17, height: 17)
                    .background(Color.rdWhite)
                    .clipShape(Circle())
                    .shadow(color: Color.rdOnyx.opacity(0.10), radius: 4, x: 0, y: 2)
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(cleanTitle)
                        .font(RDTypography.font(size: RDFontScale.size(13.5), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.level.label)
                        .font(RDTypography.font(size: RDFontScale.size(9.8), weight: .bold, design: .rounded))
                        .foregroundStyle(item.level.textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.level.bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(RDTypography.font(size: RDFontScale.size(9.8), weight: .semibold, design: .rounded))
                    Text(item.date)
                        .lineLimit(1)
                        .layoutPriority(3)
                    Text(RDLocalization.string("localizable.history.view.copy.32cf96d7", table: .localizable, fallback: "·"))
                    Text(focusText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Text(RDLocalization.string("localizable.history.view.copy.0094a905", table: .localizable, fallback: "·"))
                    Text(
                        RDLocalization.plural(
                            "analysis.count.findings",
                            table: .analysis,
                            value: item.count,
                            fallbackOne: "%lld bulgu",
                            fallbackOther: "%lld bulgu"
                        )
                    )
                        .rdMono(size: 10.5, weight: .semibold)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                }
                .font(RDTypography.font(size: RDFontScale.size(10.8), weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)

                HStack(spacing: 5) {
                    if item.status != .reviewed {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.status.textColor)
                                .frame(width: 5, height: 5)
                            Text(item.status.title)
                                .font(RDTypography.font(size: RDFontScale.size(9.8), weight: .bold, design: .rounded))
                                .foregroundStyle(item.status.textColor)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                            .background(item.status.bgColor)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    if !companyName.isEmpty {
                        Text(companyName)
                            .font(RDTypography.font(size: RDFontScale.size(9.8), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdGreenDark)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading || isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(item.level == .critical ? Color.rdCritical.opacity(0.22) : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .historyRowDepth()
        .onTapGesture {
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var rawTitleText: String {
        guard let separatorRange = item.title.range(of: " · ", options: .backwards) else {
            return item.title
        }
        return String(item.title[..<separatorRange.lowerBound])
    }

    private var cleanTitle: String {
        stripTrailingDate(from: rawTitleText)
    }

    private var focusText: String {
        let title = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.contains(" + ") {
            return title
        }
        return item.kind
    }

    private func stripTrailingDate(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"\s+\d{1,2}\s+[A-Za-zÇĞİÖŞÜçğıöşü]{3,}\s+\d{1,2}:\d{2}$"#,
            #"\s+\d{1,2}\s+[A-Za-zÇĞİÖŞÜçğıöşü]{3,}$"#,
            #"\s+Bugün\s+\d{1,2}:\d{2}$"#,
            #"\s+Dün\s+\d{1,2}:\d{2}$"#
        ]

        return patterns.reduce(trimmed) { current, pattern in
            current.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}

private extension View {
    func historyCardDepth(
        colorScheme: ColorScheme,
        accent: Color = Color.rdBlack,
        radius: CGFloat = 4,
        x: CGFloat = 5,
        y: CGFloat = 6
    ) -> some View {
        rdCardShadow(colorScheme: colorScheme, accent: accent, radius: radius, x: x, y: y)
    }

    func historyRowDepth() -> some View {
        rdRowShadow()
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppState())
}
