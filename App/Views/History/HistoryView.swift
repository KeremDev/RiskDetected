import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var search: String = ""
    @State private var activeChip: String = "Tümü"
    @State private var showFilter: Bool = false
    @State private var showCompanyFilter: Bool = false
    @State private var companies: [Company] = []
    @State private var selectedCompanyFilter: Company?
    @State private var items: [HistoryItem] = []
    @State private var analysisResult: AnalysisResultBundle? = nil
    @State private var showResult = false
    @State private var analysisError: String? = nil
    @State private var openingItemID: UUID? = nil
    @State private var deletingItemID: UUID? = nil
    @State private var itemPendingDelete: HistoryItem?
    @State private var showPaywall = false

    private let chips = ["Tümü", "Bu hafta", "Kritik", "KKD", "Genel"]
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
                LazyVStack(spacing: 12) {
                    analysisOverview
                    filterSurface

                    if filteredItems.isEmpty {
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
                title: "Analiz firma filtresi",
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
            "Analiz silinsin mi?",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { if !$0 { itemPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Analizi sil", role: .destructive) {
                if let item = itemPendingDelete {
                    deleteAnalysis(item)
                }
            }
            Button("Vazgeç", role: .cancel) {
                itemPendingDelete = nil
            }
        } message: {
            Text("Analiz, bulgular, fotoğraf kaydı ve bu analize bağlı rapor kayıtları silinir.")
        }
        .alert("Analiz Hatası", isPresented: .init(
            get: { analysisError != nil },
            set: { if !$0 { analysisError = nil } }
        )) {
            Button("Tamam") { analysisError = nil }
        } message: {
            Text(analysisError ?? "")
        }
    }

    private var analysisOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Saha taramaları")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)

                    Text("Analizlerini, kritik riskleri ve bulgu sayısını tek yerden takip et.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    Text("\(items.count)")
                        .rdMono(size: 22, weight: .bold)
                        .foregroundStyle(Color.rdWhite)
                    Text("Analiz")
                        .rdMono(size: 10, weight: .bold)
                        .foregroundStyle(Color.rdWhite.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(width: 58, height: 54)
                .background(Color.rdBlack)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.rdBlack, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .historyCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
            }

            HStack(spacing: 8) {
                overviewMetric(icon: "calendar", title: "Bu hafta", value: "\(weekCount)")
                overviewMetric(icon: "exclamationmark.triangle.fill", title: "Kritik", value: "\(criticalCount)")
                overviewMetric(icon: "checkmark.seal.fill", title: "Bulgu", value: "\(findingTotal)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#F7FBFF"),
                    Color(hex: "#F2F7FA"),
                    Color(hex: "#EEF8F2")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.rdBlack, lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .historyCardDepth(colorScheme: colorScheme, accent: Color.rdGreen, radius: 5, x: 6, y: 8)
    }

    private func overviewMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdWhite)
                .frame(width: 26, height: 26)
                .background(Color.rdWhite.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .rdMono(size: 14, weight: .bold)
                    .foregroundStyle(Color.rdWhite)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdWhite.opacity(0.70))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Color.rdBlack)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdBlack, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .historyCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
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
                    ForEach(chips, id: \.self) { c in
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

    private func filterChip(_ title: String) -> some View {
        let active = title == activeChip
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            activeChip = title
        } label: {
            HStack(spacing: 6) {
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            TextField("Analiz ara", text: $search)
                .font(.system(size: 14, design: .rounded))
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
                .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        .accessibilityLabel("Firma filtresi")
        .accessibilityIdentifier("analysis.company_filter")
    }

    private var filteredItems: [HistoryItem] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            let companyName = companyName(for: item.companyID).lowercased(with: Locale(identifier: "tr_TR"))
            let matchesSearch = needle.isEmpty
                || item.title.lowercased().contains(needle)
                || item.kind.lowercased().contains(needle)
                || companyName.contains(needle)
            let matchesCompany = selectedCompanyFilter == nil || item.companyID == selectedCompanyFilter?.id

            let matchesChip: Bool
            switch activeChip {
            case "Bu hafta":
                matchesChip = isThisWeek(item.createdAt)
            case "Kritik":
                matchesChip = item.level == .critical
            case "KKD":
                matchesChip = item.kind.localizedCaseInsensitiveContains("KKD")
            case "Genel":
                matchesChip = item.kind.localizedCaseInsensitiveContains("Genel")
            default:
                matchesChip = true
            }

            return matchesSearch && matchesChip && matchesCompany
        }
    }

    private var emptyState: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 48, height: 48)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Analiz bulunamadı")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text("Filtreyi değiştir veya yeni bir saha taraması başlat.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
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
        } catch {
            analysisError = AppErrorMessage.make(error, context: "Analizler yüklenemedi", fallbackTitle: "Analizler yüklenemedi").fullText
            items = []
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
                analysisError = AppErrorMessage.make(error, context: "Analiz açılamadı", fallbackTitle: "Analiz açılamadı").fullText
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
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: "Analiz silinemedi",
                    fallbackTitle: "Analiz silinemedi"
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
                    Label("Analizi sil", systemImage: "trash")
                }
            }
            .accessibilityAction(named: "Analizi sil") {
                onDelete()
            }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AnalysisThumbnail(path: item.photoPath, isTextAnalysis: item.isTextAnalysis, cornerRadius: 14)
                    .frame(width: 58, height: 58)

                Image(systemName: item.isTextAnalysis ? "text.alignleft" : "camera.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 20, height: 20)
                    .background(Color.rdWhite)
                    .clipShape(Circle())
                    .shadow(color: Color.rdOnyx.opacity(0.12), radius: 6, x: 0, y: 3)
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(cleanTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.level.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(item.level.textColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(item.level.bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color.rdFog, Color.rdWhite],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))

                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(item.date)
                        .lineLimit(1)
                        .layoutPriority(3)
                    Text("·")
                    Text(focusText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Text("·")
                    Text("\(item.count) bulgu")
                        .rdMono(size: 12, weight: .semibold)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)

                HStack(spacing: 6) {
                    Circle()
                        .fill(item.status.textColor)
                        .frame(width: 6, height: 6)
                    Text(item.status.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(item.status.textColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                        .background(item.status.bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !companyName.isEmpty {
                        Text(companyName)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdGreenDark)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading || isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .padding(10)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(item.level == .critical ? Color.rdCritical.opacity(0.22) : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
}
