import SwiftUI

private enum HistoryFilterChip: String, CaseIterable, Identifiable {
    case all
    case thisWeek
    case critical
    case ppe
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return RDLocalization.string(
                "localizable.history.filter.all",
                fallback: "Tümü"
            )
        case .thisWeek:
            return RDLocalization.string(
                "localizable.history.filter.this_week",
                fallback: "Bu hafta"
            )
        case .critical:
            return RDLocalization.string(
                "localizable.history.filter.critical",
                fallback: "Kritik"
            )
        case .ppe:
            return RDLocalization.string(
                "localizable.history.filter.ppe",
                fallback: "KKD"
            )
        case .general:
            return RDLocalization.string(
                "localizable.history.filter.general",
                fallback: "Genel"
            )
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var search: String = ""
    @State private var activeChip: HistoryFilterChip = .all
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
                    RDHeaderAccountCTA {
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
                .padding(.bottom, RDTabBar.contentClearance)
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
            .preferredColorScheme(preferredModalColorScheme)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(RDLocalization.string("localizable.history.view.saha.taramalari.aacc0bb4", table: .localizable, fallback: "Saha taramaları"))
                        .font(.system(size: RDFontScale.size(20), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)

                    Text(RDLocalization.string("localizable.history.view.analizlerini.kritik.riskleri.ve.bulgu.sayisini.t.2e84c78d", table: .localizable, fallback: "Analizlerini, kritik riskleri ve bulgu sayısını tek yerden takip et."))
                        .font(.system(size: RDFontScale.size(13), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    Text("\(items.count)")
                        .rdMono(size: 22, weight: .bold)
                        .foregroundStyle(Color.white)
                    Text(RDLocalization.string("localizable.history.view.analiz.c6a55aec", table: .localizable, fallback: "Analiz"))
                        .rdMono(size: 10, weight: .bold)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(width: 58, height: 54)
                .background(overviewMetricBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(overviewMetricBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .historyCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
            }

            HStack(spacing: 8) {
                overviewMetric(icon: "calendar", title: RDLocalization.string("localizable.history.view.bu.hafta.0f69ba35", table: .localizable, fallback: "Bu hafta"), value: "\(weekCount)")
                overviewMetric(icon: "exclamationmark.triangle.fill", title: RDLocalization.string("localizable.history.view.kritik.955bc760", table: .localizable, fallback: "Kritik"), value: "\(criticalCount)")
                overviewMetric(icon: "checkmark.seal.fill", title: RDLocalization.string("localizable.history.view.bulgu.24bdb5b2", table: .localizable, fallback: "Bulgu"), value: "\(findingTotal)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: overviewCardGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(overviewCardBorder, lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .historyCardDepth(colorScheme: colorScheme, accent: Color.rdGreen, radius: 5, x: 6, y: 8)
    }

    private func overviewMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .rdMono(size: 14, weight: .bold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: RDFontScale.size(10), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(overviewMetricBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(overviewMetricBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .historyCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
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
            HStack(spacing: 8) {
                searchField
                if app.currentTier.isPaid {
                    companyFilterButton
                }
                filterButton
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
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .historyCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
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
                        .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                }
                Text(chip.title)
                    .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
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
                .font(.system(size: RDFontScale.size(14), weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            TextField(RDLocalization.string("localizable.history.view.analiz.ara.39912a48", table: .localizable, fallback: "Analiz ara"), text: $search)
                .font(.system(size: RDFontScale.size(14), design: .rounded))
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
        Button {
            showFilter = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: RDFontScale.size(16), weight: .semibold, design: .rounded))
                .frame(width: 40, height: 40)
                .foregroundStyle(Color.rdBlack)
                .background(Color.rdCloud)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var companyFilterButton: some View {
        Button {
            showCompanyFilter = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: selectedCompanyFilter == nil ? "building.2" : "building.2.fill")
                .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
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
        return items.filter { item in
            let companyName = companyName(for: item.companyID).lowercased(with: .autoupdatingCurrent)
            let matchesSearch = needle.isEmpty
                || item.title.lowercased().contains(needle)
                || item.kind.lowercased().contains(needle)
                || companyName.contains(needle)
            let matchesCompany = selectedCompanyFilter == nil || item.companyID == selectedCompanyFilter?.id

            let matchesChip: Bool
            switch activeChip {
            case .thisWeek:
                matchesChip = isThisWeek(item.createdAt)
            case .critical:
                matchesChip = item.level == .critical
            case .ppe:
                matchesChip = item.kind.localizedCaseInsensitiveContains("KKD")
            case .general:
                matchesChip = item.kind.localizedCaseInsensitiveContains(
                    AnalysisCanvas.general.title
                )
            case .all:
                matchesChip = true
            }

            return matchesSearch && matchesChip && matchesCompany
        }
    }

    private var emptyState: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: RDFontScale.size(24), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 48, height: 48)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(RDLocalization.string("localizable.history.view.analiz.bulunamadi.e46caef9", table: .localizable, fallback: "Analiz bulunamadı"))
                    .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(RDLocalization.string("localizable.history.view.filtreyi.degistir.veya.yeni.bir.saha.taramasi.ba.e4cd2cb3", table: .localizable, fallback: "Filtreyi değiştir veya yeni bir saha taraması başlat."))
                    .font(.system(size: RDFontScale.size(13), design: .rounded))
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
                        .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("localizable.history.view.son.saha.taramalarin.getiriliyor.9dc0947a", table: .localizable, fallback: "Son saha taramaların getiriliyor."))
                        .font(.system(size: RDFontScale.size(13), design: .rounded))
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
                    .font(.system(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdCriticalText)
                    .frame(width: 48, height: 48)
                    .background(Color.rdCriticalBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(RDLocalization.string("localizable.history.view.analizler.yuklenemedi.c6417635", table: .localizable, fallback: "Analizler yüklenemedi"))
                        .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(message)
                        .font(.system(size: RDFontScale.size(13), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await loadItems() }
                } label: {
                    Label(RDLocalization.string("localizable.history.view.tekrar.dene.0c468462", table: .localizable, fallback: "Tekrar dene"), systemImage: "arrow.clockwise")
                        .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(8.5), weight: .bold, design: .rounded))
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
                        .font(.system(size: RDFontScale.size(13.5), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.level.label)
                        .font(.system(size: RDFontScale.size(9.8), weight: .bold, design: .rounded))
                        .foregroundStyle(item.level.textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.level.bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: RDFontScale.size(9.8), weight: .semibold, design: .rounded))
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
                .font(.system(size: RDFontScale.size(10.8), weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)

                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.status.textColor)
                            .frame(width: 5, height: 5)
                        Text(item.status.title)
                            .font(.system(size: RDFontScale.size(9.8), weight: .bold, design: .rounded))
                            .foregroundStyle(item.status.textColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                        .background(item.status.bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    if !companyName.isEmpty {
                        Text(companyName)
                            .font(.system(size: RDFontScale.size(9.8), weight: .bold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
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
