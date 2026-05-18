import SwiftUI
import OSLog

struct ReportView: View {
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "ReportView")

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var analyses: [AnalysisRow] = []
    @State private var storedReports: [ReportRow] = []
    @State private var selectedBundle: AnalysisResultBundle?
    @State private var selectedID: UUID?
    @State private var isLoading = false
    @State private var loadingID: UUID?
    @State private var downloadingID: UUID?
    @State private var deletingReportID: UUID?
    @State private var reportPendingDelete: ReportRow?
    @StateObject private var pdfGeneration = PDFGenerationProgressController()
    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var reportOptions = PDFReportOptions()
    @State private var reportCompanyLogo: UIImage?
    @State private var shareItem: ShareItem?
    @State private var showSourceReportSheet = false
    @State private var visibleReportCount = 5
    @State private var reportSearch = ""
    @State private var reportFilter: ReportArchiveFilter = .all
    @State private var reportsLoadError: String?
    @State private var canLoadMoreStoredReports = false
    @State private var isLoadingMoreStoredReports = false
    @State private var excelGenerationID: UUID?
    @State private var isStoredReportsExpanded = false
    @State private var isAnalysisSelectorExpanded = false
    @State private var reportQuotaExhausted = false
    private let reportArchivePageSize = 5
    private let reportArchiveFetchPageSize = 100
    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    reportOverview
                    reportValuePanel
                    if isLoading && storedReports.isEmpty && analyses.isEmpty {
                        loadingCard
                        storedReportsSection
                        analysisSelector
                    } else if storedReports.isEmpty && analyses.isEmpty {
                        emptyState
                    } else {
                        storedReportsSection
                        analysisSelector
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdCloud)
        .overlay {
            if pdfGeneration.isActive {
                PDFGenerationOverlay(progress: pdfGeneration.progress)
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: pdfGeneration.isActive)
        .task {
            await loadReports()
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task { await loadReports() }
        }
        .onChange(of: reportSearch) { _ in
            resetReportArchivePagination()
        }
        .onChange(of: reportFilter) { _ in
            resetReportArchivePagination()
        }
        .alert("Rapor Hatası", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $shareItem) { item in
            DocumentPreview(url: item.url)
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showSourceReportSheet) {
            if let selectedBundle {
                ReportSourceSheet(
                    bundle: selectedBundle,
                    profile: app.profile,
                    accessTier: app.currentTier,
                    canUseRiskAnalysis: app.planCapabilities.canUseDetailedRiskTable,
                    reportQuotaExhausted: reportQuotaExhausted,
                    isExcelGenerating: excelGenerationID == selectedBundle.analysis.id,
                    pdfGeneration: pdfGeneration,
                    reportOptions: $reportOptions,
                    companyLogo: $reportCompanyLogo,
                    onGenerateCustom: { options, logo in
                        generateSelectedReport(options: options, companyLogo: logo)
                    },
                    onGenerateExcel: {
                        generateExcelReport()
                    },
                    onPaywall: {
                        showSourceReportSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            showPaywall = true
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(preferredModalColorScheme)
            }
        }
        .confirmationDialog(
            "PDF raporu silinsin mi?",
            isPresented: Binding(
                get: { reportPendingDelete != nil },
                set: { if !$0 { reportPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Raporu sil", role: .destructive) {
                if let report = reportPendingDelete {
                    delete(report)
                }
            }
            Button("Vazgeç", role: .cancel) {
                reportPendingDelete = nil
            }
        } message: {
            Text("PDF dosyası ve rapor arşiv kaydı silinir. Analiz sonucu silinmez.")
        }
        .onDisappear {
            pdfGeneration.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RDHeaderLogoButton(size: 18)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                RDHeaderAccountCTA {
                    showPaywall = true
                }
            }

            HStack {
                Text("Raporlar")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(Color.rdBlack)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .zIndex(100)
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
            .preferredColorScheme(preferredModalColorScheme)
        }
    }

    private var reportOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        Text("RAPOR MERKEZİ")
                            .rdMono(size: 11, weight: .bold)
                    }
                    .foregroundStyle(Color.rdGreen)

                    Text("Denetime hazır çıktılar")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(-0.3)
                        .foregroundStyle(.white)

                    Text("Tamamlanan analizleri PDF/Excel çıktıya çevir, arşivden indir veya risk tablosuyla ayrıntılandır.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    Text("\(storedReports.count)")
                        .rdMono(size: 25, weight: .bold)
                        .foregroundStyle(.white)
                    Text("dosya")
                        .rdMono(size: 10, weight: .bold)
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(width: 66, height: 66)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            HStack(spacing: 8) {
                overviewMetric(icon: "chart.bar.doc.horizontal", title: "Kaynak", value: "\(analyses.count)")
                overviewMetric(icon: "tablecells", title: "Risk", value: "\(riskReportCount)")
                overviewMetric(icon: app.currentTier.badgeIcon, title: "Plan", value: app.currentTier.title)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                Color.rdOnyx
                Circle()
                    .fill(Color.rdGreen.opacity(0.24))
                    .frame(width: 170, height: 170)
                    .offset(x: 58, y: -76)
                Circle()
                    .fill(Color.rdGreen.opacity(0.10))
                    .frame(width: 96, height: 96)
                    .offset(x: -210, y: 92)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.rdOnyx.opacity(0.14), radius: 18, x: 0, y: 10)
    }

    private func overviewMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .rdMono(size: 14, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var reportValuePanel: some View {
        Button {
            if !app.planCapabilities.canUseDetailedRiskTable { showPaywall = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: app.planCapabilities.canUseDetailedRiskTable ? app.currentTier.badgeIcon : SubscriptionTier.plus.badgeIcon)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(app.planCapabilities.canUseDetailedRiskTable ? app.currentTier.accentTextColor : Color.white)
                    .frame(width: 42, height: 42)
                    .background(app.planCapabilities.canUseDetailedRiskTable ? app.currentTier.accentSoftColor : SubscriptionTier.plus.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.planCapabilities.canUseDetailedRiskTable ? "\(app.currentTier.title) rapor paketi aktif" : "Plus ile detaylı risk çıktısı")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Fine-Kinney ve 5×5 matris, logo, firma bilgisi ve özelleştirilmiş PDF/Excel ayarları.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if app.planCapabilities.canUseDetailedRiskTable {
                    Text("AKTİF")
                        .rdMono(size: 10, weight: .bold)
                        .foregroundStyle(Color.rdGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .padding(14)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(app.planCapabilities.canUseDetailedRiskTable ? Color.rdGreen.opacity(0.26) : Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(app.planCapabilities.canUseDetailedRiskTable)
    }

    private var storedReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            collapsibleSectionTitle(
                "Kayıtlı Rapor Dosyaları",
                meta: reportArchiveMeta,
                icon: "archivebox",
                isExpanded: $isStoredReportsExpanded
            )

            if isStoredReportsExpanded {
                if let reportsLoadError {
                    ReportArchiveStateCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Arşiv yüklenemedi",
                        subtitle: reportsLoadError,
                        tint: Color.rdCriticalText,
                        actionTitle: "Tekrar dene"
                    ) {
                        Task { await loadReports() }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if storedReports.isEmpty {
                    ReportArchiveStateCard(
                        icon: "tray",
                        title: "Henüz kayıtlı rapor yok",
                        subtitle: "PDF veya Excel oluşturduğunda dosya rapor arşivine kaydedilecek.",
                        tint: Color.rdSlate
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    VStack(spacing: 9) {
                        reportArchiveControls

                        if filteredStoredReports.isEmpty {
                            ReportArchiveStateCard(
                                icon: "magnifyingglass",
                                title: "Eşleşen rapor yok",
                                subtitle: "Arama veya filtreyi değiştirerek arşivdeki diğer dosyaları görebilirsin.",
                                tint: Color.rdSlate,
                                actionTitle: "Filtreleri temizle"
                            ) {
                                clearReportArchiveFilters()
                            }
                        }

                        ForEach(visibleStoredReports) { report in
                            StoredReportRow(
                                report: report,
                                isLoading: downloadingID == report.id,
                                isDeleting: deletingReportID == report.id
                            ) {
                                download(report)
                            } onDelete: {
                                reportPendingDelete = report
                            }
                        }

                        if visibleReportCount < filteredStoredReports.count || canLoadMoreStoredReports {
                            ReportArchiveLoadMoreButton(
                                visibleCount: min(visibleReportCount, filteredStoredReports.count),
                                totalCount: filteredStoredReports.count,
                                nextCount: nextVisibleReportCount,
                                isLoading: isLoadingMoreStoredReports,
                                hasRemoteMore: canLoadMoreStoredReports && visibleReportCount >= filteredStoredReports.count
                            ) {
                                loadMoreReports()
                            }
                            .disabled(isLoadingMoreStoredReports)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isStoredReportsExpanded)
    }

    private var reportArchiveControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)

                    TextField("Rapor ara", text: $reportSearch)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !reportSearch.isEmpty {
                        Button {
                            reportSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdSlate.opacity(0.72))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Aramayı temizle")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color.rdCloud)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if hasActiveReportArchiveFilters {
                    Button {
                        clearReportArchiveFilters()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdGreen)
                            .frame(width: 40, height: 40)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(RDPressableButtonStyle())
                    .accessibilityLabel("Rapor filtrelerini temizle")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportArchiveFilter.allCases) { filter in
                        ReportArchiveFilterChip(
                            title: filter.title,
                            count: count(for: filter),
                            isSelected: reportFilter == filter
                        ) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            reportFilter = filter
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(12)
        .background(Color.rdFog.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var analysisSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            collapsibleSectionTitle(
                "Rapora Dönüştür",
                meta: "\(analyses.count) analiz",
                icon: "wand.and.stars",
                isExpanded: $isAnalysisSelectorExpanded
            )

            if isAnalysisSelectorExpanded {
                if analyses.isEmpty {
                    ReportEmptyInlineCard(
                        icon: "doc.text.magnifyingglass",
                        title: "Rapor kaynağı bekleniyor",
                        subtitle: "Analiz tamamlandığında burada Standart Rapor veya Pro Risk Analizi üretebilirsin."
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    VStack(spacing: 9) {
                        ForEach(analyses) { row in
                            ReportAnalysisRow(
                                row: row,
                                isSelected: row.id == selectedID,
                                isLoading: row.id == loadingID
                            ) {
                                select(row)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isAnalysisSelectorExpanded)
    }

    private func collapsibleSectionTitle(
        _ title: String,
        meta: String,
        icon: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 30, height: 30)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Text(meta)
                    .rdMono(size: 11, weight: .semibold)
                    .foregroundStyle(Color.rdSlate)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 28, height: 28)
                    .background(Color.rdWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
            }
            .padding(2)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(isExpanded.wrappedValue ? "Bölümü kapatır" : "Bölümü açar")
    }

    private var riskReportCount: Int {
        storedReports.filter(\.isRiskAnalysisReport).count
    }

    private var reportArchiveMeta: String {
        if reportsLoadError != nil, storedReports.isEmpty {
            return "hata"
        }
        if storedReports.isEmpty || filteredStoredReports.count == storedReports.count {
            return "\(storedReports.count) dosya"
        }
        return "\(filteredStoredReports.count)/\(storedReports.count)"
    }

    private var filteredStoredReports: [ReportRow] {
        let needle = normalizedReportSearch(reportSearch)
        return storedReports.filter { report in
            let matchesSearch = needle.isEmpty || normalizedReportSearch(reportSearchText(for: report)).contains(needle)
            return matchesSearch && matchesReportFilter(report)
        }
    }

    private var visibleStoredReports: [ReportRow] {
        Array(filteredStoredReports.prefix(visibleReportCount))
    }

    private var hasActiveReportArchiveFilters: Bool {
        !reportSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reportFilter != .all
    }

    private var nextVisibleReportCount: Int {
        if visibleReportCount < filteredStoredReports.count {
            return min(reportArchivePageSize, filteredStoredReports.count - visibleReportCount)
        }
        return reportArchivePageSize
    }

    private var loadingCard: some View {
        RDCard {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rapor verileri hazırlanıyor")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Son tamamlanan analizler getiriliyor.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 52, height: 52)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Henüz raporlanacak analiz yok")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Fotoğraf veya metin analizi tamamlandığında rapor önizlemesi burada gerçek bulgularla oluşacak.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func matchesReportFilter(_ report: ReportRow) -> Bool {
        switch reportFilter {
        case .all:
            return true
        case .pdf:
            return !report.isExcelReport
        case .excel:
            return report.isExcelReport
        case .standard:
            return !report.isExcelReport && !report.isRiskAnalysisReport
        case .riskAnalysis:
            return report.isRiskAnalysisReport || report.isExcelReport
        case .thisWeek:
            guard let date = report.createdAt.flatMap(Self.parseReportDate) else { return false }
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    private func count(for filter: ReportArchiveFilter) -> Int {
        storedReports.filter { report in
            switch filter {
            case .all:
                return true
            case .pdf:
                return !report.isExcelReport
            case .excel:
                return report.isExcelReport
            case .standard:
                return !report.isExcelReport && !report.isRiskAnalysisReport
            case .riskAnalysis:
                return report.isRiskAnalysisReport || report.isExcelReport
            case .thisWeek:
                guard let date = report.createdAt.flatMap(Self.parseReportDate) else { return false }
                return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
            }
        }.count
    }

    private func reportSearchText(for report: ReportRow) -> String {
        [
            report.title,
            report.fileName,
            report.kind,
            report.method,
            report.format ?? "",
            report.mimeType,
            report.createdAt ?? ""
        ].joined(separator: " ")
    }

    private func normalizedReportSearch(_ value: String) -> String {
        value
            .lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetReportArchivePagination() {
        visibleReportCount = reportArchivePageSize
    }

    private func loadMoreReports() {
        if visibleReportCount < filteredStoredReports.count {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                visibleReportCount = min(visibleReportCount + reportArchivePageSize, filteredStoredReports.count)
            }
            return
        }

        guard canLoadMoreStoredReports, !isLoadingMoreStoredReports else { return }
        isLoadingMoreStoredReports = true
        Task {
            let startedAt = Date()
            let offset = storedReports.count
            do {
                let moreReports = try await AnalysisService.shared.listReports(
                    limit: reportArchiveFetchPageSize,
                    offset: offset
                )
                await MainActor.run {
                    appendStoredReports(moreReports)
                    canLoadMoreStoredReports = moreReports.count == reportArchiveFetchPageSize
                    reportsLoadError = nil
                    visibleReportCount = min(
                        visibleReportCount + reportArchivePageSize,
                        max(filteredStoredReports.count, visibleReportCount)
                    )
                    isLoadingMoreStoredReports = false
                    logReportArchiveTelemetry(
                        event: "load_more",
                        duration: Date().timeIntervalSince(startedAt),
                        fetchedCount: moreReports.count,
                        cachedCount: storedReports.count,
                        offset: offset,
                        hasRemoteMore: canLoadMoreStoredReports
                    )
                }
            } catch {
                await MainActor.run {
                    Self.logger.error("Report archive load_more failed offset=\(offset, privacy: .public) duration_ms=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    errorMessage = AppErrorMessage.make(
                        error,
                        context: "Rapor arşivi yüklenemedi",
                        fallbackTitle: "Rapor arşivi yüklenemedi"
                    ).fullText
                    isLoadingMoreStoredReports = false
                }
            }
        }
    }

    private func clearReportArchiveFilters() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            reportSearch = ""
            reportFilter = .all
            resetReportArchivePagination()
        }
    }

    private static func parseReportDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func loadReports() async {
        guard app.auth.session != nil else {
            analyses = []
            storedReports = []
            selectedBundle = nil
            selectedID = nil
            reportsLoadError = nil
            canLoadMoreStoredReports = false
            isLoadingMoreStoredReports = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let archiveStartedAt = Date()
            async let analysisRows = AnalysisService.shared.listRecent(limit: 12)
            async let reportRows = AnalysisService.shared.listReports(limit: reportArchiveFetchPageSize)
            let rows = try await analysisRows
            do {
                let reports = try await reportRows
                storedReports = reports
                canLoadMoreStoredReports = reports.count == reportArchiveFetchPageSize
                reportsLoadError = nil
                logReportArchiveTelemetry(
                    event: "initial_load",
                    duration: Date().timeIntervalSince(archiveStartedAt),
                    fetchedCount: reports.count,
                    cachedCount: storedReports.count,
                    offset: 0,
                    hasRemoteMore: canLoadMoreStoredReports
                )
            } catch {
                Self.logger.error("Report archive initial_load failed duration_ms=\(Int(Date().timeIntervalSince(archiveStartedAt) * 1000), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                reportsLoadError = AppErrorMessage.make(
                    error,
                    context: "Rapor arşivi yüklenemedi",
                    fallbackTitle: "Rapor arşivi yüklenemedi"
                ).fullText
                storedReports = []
                canLoadMoreStoredReports = false
            }
            visibleReportCount = min(visibleReportCount, max(filteredStoredReports.count, reportArchivePageSize))
            analyses = rows
            selectedBundle = nil
            selectedID = nil
        } catch {
            errorMessage = AppErrorMessage.make(error, context: "Raporlar yüklenemedi", fallbackTitle: "Raporlar yüklenemedi").fullText
            analyses = []
            storedReports = []
            selectedBundle = nil
            selectedID = nil
            reportsLoadError = nil
            canLoadMoreStoredReports = false
            isLoadingMoreStoredReports = false
        }
    }

    private func logReportArchiveTelemetry(
        event: String,
        duration: TimeInterval,
        fetchedCount: Int,
        cachedCount: Int,
        offset: Int,
        hasRemoteMore: Bool
    ) {
        Self.logger.info("Report archive \(event, privacy: .public) duration_ms=\(Int(duration * 1000), privacy: .public) fetched=\(fetchedCount, privacy: .public) cached=\(cachedCount, privacy: .public) offset=\(offset, privacy: .public) remote_more=\(hasRemoteMore, privacy: .public) filter=\(reportFilter.rawValue, privacy: .public) filters_active=\(hasActiveReportArchiveFilters, privacy: .public)")
    }

    private func select(_ row: AnalysisRow) {
        guard loadingID == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedID = row.id
        loadingID = row.id

        Task {
            do {
                selectedBundle = try await AnalysisService.shared.result(analysisID: row.id)
                reportOptions = defaultReportOptions(kind: reportOptions.kind == .standard ? .riskAnalysis : reportOptions.kind)
                await app.refreshPlanState()
                _ = await refreshReportQuotaState()
                _ = try? await loadProfileLogoIfNeeded()
                showSourceReportSheet = true
            } catch {
                errorMessage = AppErrorMessage.make(error, context: "Analiz rapora açılamadı", fallbackTitle: "Analiz rapora açılamadı").fullText
            }
            loadingID = nil
        }
    }

    private func generateSelectedReport(options: PDFReportOptions? = nil, companyLogo: UIImage? = nil) {
        guard !pdfGeneration.isActive else { return }
        guard let selectedBundle else {
            errorMessage = AppErrorMessage.make(
                AnalysisService.AnalysisError.invalidInput("PDF oluşturmak için tamamlanmış bir analiz seçmelisin."),
                context: "PDF oluşturulamadı",
                fallbackTitle: "PDF oluşturulamadı"
            ).fullText
            return
        }
        guard let userID = app.auth.session?.user.id else {
            errorMessage = AppErrorMessage.make(AnalysisService.AnalysisError.notAuthenticated, context: "Rapor kaydedilemedi").fullText
            return
        }

        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        pdfGeneration.start()
        Task {
            do {
                if await refreshReportQuotaState() {
                    pdfGeneration.stop()
                    reportOptions.kind = .standard
                    showSourceReportSheet = true
                    return
                }
                let reportImage = try await loadReportImage(for: selectedBundle)
                pdfGeneration.advance(to: 0.23)
                let resolvedOptions = options ?? defaultReportOptions(kind: .standard)
                let resolvedLogo = try await loadProfileLogoIfNeeded()
                let input = PDFReportService.ReportInput(
                    bundle: selectedBundle,
                    findings: sortedFindings(selectedBundle.findings.map(\.asFinding), method: resolvedOptions.method),
                    profile: app.profile,
                    image: reportImage,
                    companyLogo: companyLogo ?? resolvedLogo,
                    options: resolvedOptions
                )
                let url = try await PDFReportService.shared.generateAsync(input: input)
                pdfGeneration.advance(to: 0.71)
                var archiveWarning: String?
                do {
                    let report = try await AnalysisService.shared.storeReport(
                        userID: userID,
                        bundle: selectedBundle,
                        fileURL: url,
                        kind: resolvedOptions.kind,
                        method: resolvedOptions.method,
                        requestID: requestID,
                        supportID: supportID
                    )
                    mergeStoredReport(report)
                } catch {
                    Self.logger.error("Report archive failed after PDF generation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    if AppErrorMessage.isReportQuotaExceeded(error.localizedDescription) {
                        throw error
                    } else {
                        archiveWarning = AppErrorMessage.make(
                            rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                            context: "Rapor arşive kaydedilemedi",
                            fallbackTitle: "Rapor arşive kaydedilemedi"
                        ).fullText
                    }
                }
                pdfGeneration.advance(to: 0.88)
                pdfGeneration.advance(to: 0.94)
                await pdfGeneration.complete()
                if let archiveWarning {
                    errorMessage = archiveWarning
                }
                shareItem = ShareItem(url: url)
            } catch {
                pdfGeneration.stop()
                if handleReportQuotaIfNeeded(error) {
                    return
                }
                errorMessage = AppErrorMessage.make(
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: "PDF oluşturulamadı",
                    fallbackTitle: "PDF oluşturulamadı"
                ).fullText
            }
        }
    }

    private func generateExcelReport() {
        guard let selectedBundle else { return }
        guard excelGenerationID == nil else { return }
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        excelGenerationID = selectedBundle.analysis.id

        Task {
            do {
                if await refreshReportQuotaState() {
                    reportOptions.kind = .standard
                    showSourceReportSheet = true
                    excelGenerationID = nil
                    return
                }
                let report = try await AnalysisService.shared.generateExcelReport(
                    analysisID: selectedBundle.analysis.id,
                    method: reportOptions.method,
                    language: reportOptions.language,
                    requestID: requestID,
                    supportID: supportID
                )
                mergeStoredReport(report)
                let url = try await AnalysisService.shared.reportFileURL(
                    for: report,
                    requestID: requestID,
                    supportID: supportID
                )
                shareItem = ShareItem(url: url)
            } catch {
                if handleReportQuotaIfNeeded(error) {
                    excelGenerationID = nil
                    return
                }
                errorMessage = AppErrorMessage.make(
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: "Excel oluşturulamadı",
                    fallbackTitle: "Excel oluşturulamadı"
                ).fullText
            }
            excelGenerationID = nil
        }
    }

    private func mergeStoredReport(_ report: ReportRow) {
        reportsLoadError = nil
        storedReports.removeAll { $0.id == report.id || $0.storagePath == report.storagePath }
        storedReports.insert(report, at: 0)
        visibleReportCount = max(visibleReportCount, min(filteredStoredReports.count, reportArchivePageSize))
    }

    private func appendStoredReports(_ reports: [ReportRow]) {
        guard !reports.isEmpty else { return }
        let existingIDs = Set(storedReports.map(\.id))
        let existingPaths = Set(storedReports.map(\.storagePath))
        let uniqueReports = reports.filter { !existingIDs.contains($0.id) && !existingPaths.contains($0.storagePath) }
        storedReports.append(contentsOf: uniqueReports)
    }

    @discardableResult
    private func handleReportQuotaIfNeeded(_ error: Error) -> Bool {
        guard AppErrorMessage.isReportQuotaExceeded(error.localizedDescription) else { return false }
        reportQuotaExhausted = true
        reportOptions.kind = .standard
        showSourceReportSheet = true
        return true
    }

    private func refreshReportQuotaState() async -> Bool {
        do {
            let usage = try await AnalysisService.shared.monthlyReportQuotaUsage(tier: app.profile?.tier ?? app.currentTier)
            reportQuotaExhausted = usage.isExhausted
        } catch {
            reportQuotaExhausted = false
        }
        return reportQuotaExhausted
    }

    private func download(_ report: ReportRow) {
        guard downloadingID == nil else { return }
        downloadingID = report.id
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()

        Task {
            do {
                let url = try await AnalysisService.shared.reportFileURL(
                    for: report,
                    requestID: requestID,
                    supportID: supportID
                )
                shareItem = ShareItem(url: url)
            } catch {
                errorMessage = AppErrorMessage.make(
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: "Rapor indirilemedi",
                    fallbackTitle: "Rapor indirilemedi"
                ).fullText
            }
            downloadingID = nil
        }
    }

    private func delete(_ report: ReportRow) {
        guard deletingReportID == nil else { return }
        reportPendingDelete = nil
        deletingReportID = report.id
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()

        Task {
            do {
                try await AnalysisService.shared.deleteReport(
                    report,
                    requestID: requestID,
                    supportID: supportID
                )
                storedReports.removeAll { $0.id == report.id }
                visibleReportCount = min(visibleReportCount, max(filteredStoredReports.count, reportArchivePageSize))
            } catch {
                errorMessage = AppErrorMessage.make(
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: "Rapor silinemedi",
                    fallbackTitle: "Rapor silinemedi"
                ).fullText
            }
            deletingReportID = nil
        }
    }

    private func loadReportImage(for bundle: AnalysisResultBundle) async throws -> UIImage? {
        guard let path = bundle.photos.first?.storagePath else { return nil }
        let data = try await AnalysisService.shared.photoData(path: path)
        guard let image = UIImage(data: data) else {
            throw AnalysisService.AnalysisError.storageFailed("Analiz fotoğrafı indirildi ancak görüntü formatı açılamadı.")
        }
        return image
    }

    private func defaultReportOptions(kind: PDFReportKind = .standard) -> PDFReportOptions {
        PDFReportOptions(
            kind: kind,
            method: app.profile?.preferredMethod?.domain ?? .fineKinney,
            preparedBy: app.profile?.displayName ?? "",
            preparedTitle: app.profile?.title ?? "",
            certificateNumber: app.profile?.certificateNumber ?? "",
            companyName: app.profile?.companyName ?? "",
            companyInfo: app.profile?.phone ?? "",
            language: app.languagePreference
        )
    }

    @discardableResult
    private func loadProfileLogoIfNeeded() async throws -> UIImage? {
        if let reportCompanyLogo { return reportCompanyLogo }
        guard let path = app.profile?.companyLogoURL, !path.isEmpty else { return nil }
        let image = try await app.auth.profileLogoImage(path: path)
        await MainActor.run {
            reportCompanyLogo = image
        }
        return image
    }

    private func sortedFindings(_ findings: [Finding], method: RiskMethod) -> [Finding] {
        findings.sorted {
            let leftRank = rankFor($0.band(for: method).level)
            let rightRank = rankFor($1.band(for: method).level)
            if leftRank != rightRank { return leftRank > rightRank }

            let leftScore = $0.score(for: method)
            let rightScore = $1.score(for: method)
            if leftScore != rightScore { return leftScore > rightScore }

            return $0.confidence > $1.confidence
        }
    }

    private func rankFor(_ level: RiskLevel) -> Int {
        switch level {
        case .critical: return 4
        case .high:     return 3
        case .medium:   return 2
        case .low:      return 1
        case .unknown:  return 0
        }
    }
}

private struct ReportPreview: View {
    let bundle: AnalysisResultBundle
    let profile: UserProfile?

    private var analysis: AnalysisRow { bundle.analysis }
    private var findings: [Finding] { bundle.findings.map(\.asFinding) }
    private var photoPath: String? { bundle.photos.first?.storagePath }
    private var isTextAnalysis: Bool { analysis.kind == "text" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            reportHeader
            titleBlock
            summaryGrid

            if let summary = analysis.aiSummary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.rdCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if findings.isEmpty {
                noFindingsBlock
            } else {
                findingsTable
            }

            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.10), radius: 28, x: 0, y: 12)
    }

    private var reportHeader: some View {
        HStack(alignment: .top) {
            RDLogo(size: 13)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedDate)
                    .rdMono(size: 10, weight: .semibold)
                Text("#\(documentNo)")
                    .rdMono(size: 10)
            }
            .foregroundStyle(Color.rdSlate)
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rdSelected)
                .frame(height: 2)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("İş Güvenliği Risk Analizi")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(Color.rdBlack)
                Text("\(analysis.title) · \(canvasLabel)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
                Text(methodSummary)
                    .rdMono(size: 10)
                    .foregroundStyle(Color.rdSlate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AnalysisThumbnail(path: photoPath, isTextAnalysis: isTextAnalysis, cornerRadius: 8)
                .frame(width: 64, height: 64)
        }
    }

    private var summaryGrid: some View {
        HStack(spacing: 6) {
            miniBadge(level: .critical)
            miniBadge(level: .high)
            miniBadge(level: .medium)
            miniBadge(level: .low)
        }
    }

    private var findingsTable: some View {
        VStack(spacing: 0) {
            tableHeader
            ForEach(Array(findings.prefix(6).enumerated()), id: \.element.id) { idx, finding in
                tableRow(idx: idx + 1, finding: finding)
                if idx < min(findings.count, 6) - 1 {
                    Divider().background(Color.rdLine)
                }
            }

            if findings.count > 6 {
                Text("+ \(findings.count - 6) bulgu raporun devamında")
                    .rdMono(size: 10, weight: .semibold)
                    .foregroundStyle(Color.rdSlate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 6)
    }

    private var noFindingsBlock: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdLow)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tehlike tespit edilmedi")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text("Bu analiz için AI bulgu kaydı dönmedi.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdLowBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        Text("Sayfa 1 / \(max(Int(ceil(Double(max(findings.count, 1)) / 6.0)), 1)) · İSG Uzmanı: \(expertName) · \(expertCredential)")
            .rdMono(size: 10)
            .foregroundStyle(Color.rdSlate)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.rdFog)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, 10)
    }

    private func miniBadge(level: RiskLevel) -> some View {
        let count = findings.filter { $0.fkBand.level == level }.count
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(count)")
                .rdMono(size: 16, weight: .bold)
                .foregroundStyle(level.textColor)
            Text(level.shortLabel)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(level.textColor)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level.bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: 20, alignment: .leading)
            Text("RİSK").frame(maxWidth: .infinity, alignment: .leading)
            Text("FK").frame(width: 48, alignment: .leading)
            Text("5×5").frame(width: 44, alignment: .leading)
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .tracking(0.7)
        .foregroundStyle(Color.rdSlate)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rdLine).frame(height: 1)
        }
    }

    private func tableRow(idx: Int, finding: Finding) -> some View {
        HStack(spacing: 6) {
            Text("\(idx)")
                .rdMono(size: 11, weight: .semibold)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(2)
                Text(finding.category)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(scoreText(finding.fkScore))
                .rdMono(size: 10, weight: .semibold)
                .foregroundStyle(finding.fkBand.level.textColor)
                .frame(width: 48, alignment: .leading)
            Text("\(finding.m5Score)")
                .rdMono(size: 10, weight: .semibold)
                .foregroundStyle(finding.m5Band.level.textColor)
                .frame(width: 44, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private var canvasLabel: String {
        AnalysisCanvas.all.first(where: { $0.id == analysis.canvas })?.title ?? analysis.canvas.capitalized
    }

    private var formattedDate: String {
        guard let date = analysis.createdAt.flatMap(Self.parseDate) else { return "Tarih yok" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM yyyy · HH:mm"
        return formatter.string(from: date)
    }

    private var documentNo: String {
        String(analysis.id.uuidString.prefix(8)).uppercased()
    }

    private var methodSummary: String {
        "Fine-Kinney toplam: \(scoreText(analysis.totalScoreFK ?? 0)) · 5×5 toplam: \(analysis.totalScoreM5 ?? 0)"
    }

    private var expertName: String {
        profile?.displayName ?? "Kullanıcı"
    }

    private var expertCredential: String {
        profile?.certificateNumber ?? profile?.title ?? "İSG Uzmanı"
    }

    private func scoreText(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

private struct ReportSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let bundle: AnalysisResultBundle
    let profile: UserProfile?
    let accessTier: SubscriptionTier
    let canUseRiskAnalysis: Bool
    let reportQuotaExhausted: Bool
    let isExcelGenerating: Bool
    @ObservedObject var pdfGeneration: PDFGenerationProgressController
    @Binding var reportOptions: PDFReportOptions
    @Binding var companyLogo: UIImage?
    let onGenerateCustom: (PDFReportOptions, UIImage?) -> Void
    let onGenerateExcel: () -> Void
    let onPaywall: () -> Void
    @State private var showSettings = false
    @State private var reportSettingsDetent: PresentationDetent = .height(440)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                sheetHeader
                ReportPreview(bundle: bundle, profile: profile)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.rdCloud)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            reportActionsBar
        }
        .sheet(isPresented: $showSettings) {
            ReportSettingsSheet(
                options: $reportOptions,
                companyLogo: $companyLogo,
                presentationDetent: $reportSettingsDetent,
                profile: profile,
                accessTier: accessTier,
                canUseRiskAnalysis: canUseRiskAnalysis,
                reportQuotaExhausted: reportQuotaExhausted,
                onGenerate: {
                    showSettings = false
                    onGenerateCustom(reportOptions, companyLogo)
                },
                onGenerateExcel: {
                    showSettings = false
                    onGenerateExcel()
                },
                onPaywall: {
                    showSettings = false
                    onPaywall()
                },
                onClose: { showSettings = false }
            )
            .presentationDetents([.height(440), .large], selection: $reportSettingsDetent)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(colorScheme)
        }
    }

    private var reportActionsBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.rdCloud.opacity(0), Color.rdCloud],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 14)

            reportActions
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(Color.rdCloud)
        }
    }

    private var sheetHeader: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 40, height: 40)
                    .background(Color.rdWhite.opacity(0.96))
                    .clipShape(Circle())
                    .shadow(color: Color.rdOnyx.opacity(0.14), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(RDPressableButtonStyle())
            .accessibilityLabel("Pencereyi kapat")
        }
    }

    private var reportActions: some View {
        RDButton(
            title: isExcelGenerating ? "Excel hazırlanıyor..." : pdfGeneration.isActive ? "Rapor hazırlanıyor..." : "Rapor oluştur",
            style: .primary,
            icon: isExcelGenerating ? "hourglass" : "slider.horizontal.3",
            height: 56
        ) {
            reportOptions = PDFReportOptions(
                kind: .standard,
                method: profile?.preferredMethod?.domain ?? reportOptions.method,
                preparedBy: profile?.displayName ?? "",
                preparedTitle: profile?.title ?? "",
                certificateNumber: profile?.certificateNumber ?? "",
                companyName: profile?.companyName ?? "",
                companyInfo: profile?.phone ?? "",
                language: reportOptions.language
            )
            reportSettingsDetent = .height(440)
            showSettings = true
        }
        .disabled(isExcelGenerating || pdfGeneration.isActive)
    }
}

private struct ReportAnalysisRow: View {
    let row: AnalysisRow
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.kind == "text" ? "text.alignleft" : "camera.viewfinder")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(level.textColor)
                    .frame(width: 44, height: 44)
                    .background(level.bgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(level.label)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(level.textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(level.bgColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(spacing: 6) {
                        Label(dateText, systemImage: "calendar")
                        Text("·")
                        Text(canvasLabel)
                        Text("·")
                        Text("\(row.findingCount) bulgu")
                            .rdMono(size: 12, weight: .semibold)
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.rdGreen : Color.rdSlate)
                }
            }
            .padding(14)
            .background(isSelected ? Color.rdGreenSoft : Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.rdGreen.opacity(0.35) : Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var level: RiskLevel {
        RiskLevel(rawValue: row.highestBandFK ?? row.highestBandM5 ?? "unknown") ?? .unknown
    }

    private var canvasLabel: String {
        AnalysisCanvas.all.first(where: { $0.id == row.canvas })?.title ?? row.canvas.capitalized
    }

    private var dateText: String {
        guard let date = row.createdAt.flatMap(Self.parseDate) else { return "Tarih yok" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

private struct ReportEmptyInlineCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 42, height: 42)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private enum ReportArchiveFilter: String, CaseIterable, Identifiable {
    case all
    case pdf
    case excel
    case standard
    case riskAnalysis
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tümü"
        case .pdf: return "PDF"
        case .excel: return "Excel"
        case .standard: return "Standart"
        case .riskAnalysis: return "Risk analizi"
        case .thisWeek: return "Bu hafta"
        }
    }
}

private struct ReportArchiveFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))

                Text("\(count)")
                    .rdMono(size: 10, weight: .bold)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.74) : Color.rdSlate)
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .foregroundStyle(isSelected ? Color.white : Color.rdCharcoal)
            .background(isSelected ? Color.rdSelected : Color.rdWhite)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.rdSelected : Color.rdLine, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) rapor")
    }
}

private struct ReportArchiveStateCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 6) {
                            Image(systemName: actionTitle.localizedCaseInsensitiveContains("tekrar") ? "arrow.clockwise" : "xmark.circle")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            Text(actionTitle)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.rdBlack)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.rdFog)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.rdLine, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(RDPressableButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ReportArchiveLoadMoreButton: View {
    let visibleCount: Int
    let totalCount: Int
    let nextCount: Int
    let isLoading: Bool
    let hasRemoteMore: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: hasRemoteMore ? "arrow.down.circle.fill" : "plus")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.rdGreen)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? "Yükleniyor" : hasRemoteMore ? "Arşivden devamını yükle" : "Daha fazla yükle")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(hasRemoteMore ? "\(visibleCount) eşleşen rapor gösteriliyor" : "\(visibleCount)/\(totalCount) gösteriliyor")
                        .rdMono(size: 10, weight: .semibold)
                        .foregroundStyle(Color.rdSlate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isLoading {
                    Text("+\(nextCount)")
                        .rdMono(size: 11, weight: .bold)
                        .foregroundStyle(Color.rdSlate)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.rdFog)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(10)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(RDPressableButtonStyle())
    }
}

private struct StoredReportRow: View {
    let report: ReportRow
    let isLoading: Bool
    let isDeleting: Bool
    let action: () -> Void
    let onDelete: () -> Void

    var body: some View {
        rowContent
            .contextMenu {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Raporu sil", systemImage: "trash")
                }
            }
            .accessibilityAction(named: "Raporu sil") {
                onDelete()
            }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isRiskAnalysis ? Color.rdGreenSoft : Color.rdFog)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isRiskAnalysis ? Color.rdGreen : Color.rdCharcoal)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reportTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let titleDateText {
                        Text(titleDateText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color.rdFog, Color.rdWhite],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))

                HStack(spacing: 7) {
                    Text(kindLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(kindStyle.text)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(kindStyle.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: true, vertical: false)

                    Text(methodLabel)
                        .rdMono(size: 10, weight: .bold)
                        .foregroundStyle(Color.rdCharcoal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.rdFog)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: true, vertical: false)

                    Text(statusLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(statusStyle.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(statusStyle.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(dateText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading || isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 38, height: 38)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isRiskAnalysis ? Color.rdGreen.opacity(0.24) : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }

    private var iconName: String {
        if isExcel { return "tablecells.fill" }
        return isRiskAnalysis ? "tablecells" : "doc.richtext"
    }

    private var isExcel: Bool {
        report.isExcelReport
    }

    private var isRiskAnalysis: Bool {
        report.isRiskAnalysisReport
    }

    private var kindLabel: String {
        if isExcel { return "Excel tablo" }
        return isRiskAnalysis ? "Risk analizi" : "Standart rapor"
    }

    private var kindStyle: (text: Color, background: Color) {
        if isExcel {
            return (Color(hex: "#2563EB"), Color(hex: "#EAF1FF"))
        }
        if isRiskAnalysis {
            return (Color.rdGreen, Color.rdGreenSoft)
        }
        return (Color(hex: "#6D5DF6"), Color(hex: "#EFEDFF"))
    }

    private var methodLabel: String {
        if report.method == RiskMethod.matrix5x5.rawValue || report.method == "matrix_5x5" {
            return "5x5"
        }
        return "FK"
    }

    private var statusLabel: String {
        if isDeleting { return "Siliniyor" }
        if isLoading { return "Açılıyor" }
        return "Hazır"
    }

    private var statusStyle: (text: Color, background: Color) {
        if isDeleting {
            return (Color.rdCriticalText, Color.rdCriticalBg.opacity(0.75))
        }
        if isLoading {
            return (Color.rdHighText, Color.rdHighBg.opacity(0.75))
        }
        return (Color.rdLowText, Color.rdLowBg.opacity(0.8))
    }

    private var reportTitle: String {
        guard let separatorRange = report.title.range(of: " · ", options: .backwards) else {
            return report.title
        }
        return String(report.title[..<separatorRange.lowerBound])
    }

    private var titleDateText: String? {
        guard let separatorRange = report.title.range(of: " · ", options: .backwards) else {
            return nil
        }
        let suffix = String(report.title[separatorRange.upperBound...])
        return suffix.isEmpty ? nil : suffix
    }

    private var dateText: String {
        guard let date = report.createdAt.flatMap(Self.parseDate) else { return "Tarih yok" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

#Preview {
    ReportView()
        .environmentObject(AppState())
}
