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
    @State private var selectedReportCompany: Company?
    @State private var profileReportLogo: UIImage?
    @State private var shareItem: ShareItem?
    @State private var showSourceReportSheet = false
    @State private var visibleReportCount = 5
    @State private var reportSearch = ""
    @State private var reportFilter: ReportArchiveFilter = .all
    @State private var companies: [Company] = []
    @State private var selectedCompanyFilter: Company?
    @State private var showCompanyFilter = false
    @State private var reportsLoadError: String?
    @State private var canLoadMoreStoredReports = false
    @State private var isLoadingMoreStoredReports = false
    @State private var excelGenerationID: UUID?
    @State private var isStoredReportsExpanded = false
    @State private var isAnalysisSelectorExpanded = false
    @State private var reportQuotaExhausted = false
    @State private var freeRiskAnalysisTrialUsed = false
    private let reportArchivePageSize = 5
    private let reportArchiveFetchPageSize = 100
    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }
    private var freeRiskAnalysisTrialRemaining: Int {
        app.currentTier == .free && !freeRiskAnalysisTrialUsed ? 1 : 0
    }
    private var reportCardFill: Color {
        colorScheme == .dark ? Color(hex: "#151A18") : Color.rdWhite
    }
    private var reportCardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.rdLine
    }
    private var reportInsetFill: Color {
        colorScheme == .dark ? Color(hex: "#202526") : Color.rdFog
    }
    private var reportMetaText: Color {
        colorScheme == .dark ? Color.white.opacity(0.74) : Color.rdSlate
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    reportOverview
                    if !app.planCapabilities.canUseDetailedRiskTable {
                        reportValuePanel
                    }
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
                .padding(.bottom, 24)
            }
        }
        .background(Color.rdCloud)
        .accessibilityIdentifier("report.root")
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
        .onChange(of: selectedCompanyFilter?.id) { _ in
            resetReportArchivePagination()
        }
        .alert(RDLocalization.string("reports.report.view.rapor.hatasi.3b5b8533", table: .reports, fallback: "Rapor Hatası"), isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(RDLocalization.string("reports.report.view.tamam.8d82c31b", table: .reports, fallback: "Tamam")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $shareItem) { item in
            DocumentPreview(url: item.url)
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showCompanyFilter) {
            CompanyPickerSheet(
                title: RDLocalization.string("reports.report.view.rapor.firma.filtresi.e0cc0fc3", table: .reports, fallback: "Rapor firma filtresi"),
                accessTier: app.currentTier,
                selectedCompanyID: selectedCompanyFilter?.id,
                allowNoCompany: true,
                onSelect: { company in
                    selectedCompanyFilter = company
                },
                onPaywall: {
                    PaywallEventService.shared.beginEntry(
                        at: .reportsCompanyPicker,
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
        .sheet(isPresented: $showSourceReportSheet) {
            if let selectedBundle {
                ReportSourceSheet(
                    bundle: selectedBundle,
                    profile: app.profile,
                    accessTier: app.currentTier,
                    canUseRiskAnalysis: app.planCapabilities.canUseDetailedRiskTable,
                    freeRiskAnalysisTrialRemaining: freeRiskAnalysisTrialRemaining,
                    reportQuotaExhausted: reportQuotaExhausted,
                    isExcelGenerating: excelGenerationID == selectedBundle.analysis.id,
                    pdfGeneration: pdfGeneration,
                    reportOptions: $reportOptions,
                    selectedCompany: $selectedReportCompany,
                    companyLogo: $profileReportLogo,
                    onGenerateCustom: { options, logo in
                        generateSelectedReport(options: options, companyLogo: logo)
                    },
                    onGenerateExcel: {
                        generateExcelReport()
                    },
                    onPaywall: { placement in
                        showSourceReportSheet = false
                        PaywallEventService.shared.beginEntry(
                            at: placement == .companyPicker
                                ? .reportsReportCompanyPicker
                                : .reportsLockedReportOptions,
                            currentTier: app.currentTier,
                            targetTier: app.currentTier == .plus ? .pro : .plus
                        )
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
            RDLocalization.string("reports.report.view.pdf.raporu.silinsin.mi.abd25be0", table: .reports, fallback: "PDF raporu silinsin mi?"),
            isPresented: Binding(
                get: { reportPendingDelete != nil },
                set: { if !$0 { reportPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(RDLocalization.string("reports.report.view.raporu.sil.b9373641", table: .reports, fallback: "Raporu sil"), role: .destructive) {
                if let report = reportPendingDelete {
                    delete(report)
                }
            }
            Button(RDLocalization.string("reports.report.view.vazgec.9e22fb3c", table: .reports, fallback: "Vazgeç"), role: .cancel) {
                reportPendingDelete = nil
            }
        } message: {
            Text(RDLocalization.string("reports.report.view.pdf.dosyasi.ve.rapor.arsiv.kaydi.silinir.analiz..9a8805b0", table: .reports, fallback: "PDF dosyası ve rapor arşiv kaydı silinir. Analiz sonucu silinmez."))
        }
        .onDisappear {
            pdfGeneration.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RDHeaderLogoButton(size: 18)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                RDHeaderAccountCTA(
                    directEntryPoint: .reportsHeaderUpgrade,
                    menuEntryPoint: .reportsHeaderProfileMenuUpgrade
                ) {
                    showPaywall = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .zIndex(100)
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
            .preferredColorScheme(.dark)
        }
    }

    private var reportOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(NovaFont.font(.screenTitle))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(RDLocalization.string("reports.report.view.denetime.hazir.ciktilar.57e9283a", table: .reports, fallback: "Denetime hazır çıktılar"))
                        .font(NovaFont.font(.screenTitle))
                        .foregroundStyle(Color.rdBlack)

                    Text(RDLocalization.string("reports.report.view.pdf.excel.ve.risk.tablolarini.tek.yerden.yonet.e98bd72a", table: .reports, fallback: "PDF, Excel ve risk tablolarını tek yerden yönet."))
                        .font(NovaFont.font(.body))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    Text("\(storedReports.count)")
                        .rdMono(size: 22, weight: .bold)
                        .foregroundStyle(overviewMetricPrimaryText)
                    Text(RDLocalization.string("reports.report.view.dosya.f970b19d", table: .reports, fallback: "dosya"))
                        .rdMono(size: 10, weight: .bold)
                        .foregroundStyle(overviewMetricSecondaryText)
                }
                .frame(width: 58, height: 54)
                .background(overviewMetricBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(overviewMetricBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .reportCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
            }

            HStack(spacing: 8) {
                overviewMetric(icon: "chart.bar.doc.horizontal", title: RDLocalization.string("reports.report.view.analiz.07136742", table: .reports, fallback: "Analiz"), value: "\(analyses.count)")
                overviewMetric(icon: "tablecells", title: RDLocalization.string("reports.report.view.risk.tablosu.1dc67ffd", table: .reports, fallback: "Risk Tablosu"), value: "\(riskReportCount)")
                overviewMetric(icon: "archivebox.fill", title: RDLocalization.string("reports.report.view.arsiv.578e3fea", table: .reports, fallback: "Arşiv"), value: "\(storedReports.count)")
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
        .reportCardDepth(colorScheme: colorScheme, accent: Color.rdGreen, radius: 5, x: 6, y: 8)
    }

    private func overviewMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(NovaFont.font(.meta))
                .foregroundStyle(overviewMetricIconText)
                .frame(width: 26, height: 26)
                .background(overviewMetricIconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .rdMono(size: 14, weight: .bold)
                    .foregroundStyle(overviewMetricPrimaryText)
                    .lineLimit(1)
                Text(title)
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(overviewMetricSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
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
        .reportCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
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
        colorScheme == .dark ? Color(hex: "#17231B") : Color.rdOnyx
    }

    private var overviewMetricBorder: Color {
        colorScheme == .dark ? Color.rdGreen.opacity(0.34) : Color.rdOnyx
    }

    private var overviewMetricPrimaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.rdWhite
    }

    private var overviewMetricSecondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.rdWhite.opacity(0.70)
    }

    private var overviewMetricIconText: Color {
        colorScheme == .dark ? Color.rdGreen : Color.rdWhite
    }

    private var overviewMetricIconBackground: Color {
        colorScheme == .dark ? Color.rdGreen.opacity(0.16) : Color.rdWhite.opacity(0.14)
    }

    private var reportValuePanel: some View {
        RDPlanUpsellCard {
            PaywallEventService.shared.beginEntry(
                at: .reportsUpsellCard,
                currentTier: app.currentTier,
                targetTier: app.currentTier == .plus ? .pro : .plus
            )
            showPaywall = true
        }
    }

    private var storedReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            collapsibleSectionTitle(
                RDLocalization.string("reports.report.view.kayitli.rapor.dosyalari.bd41e3d0", table: .reports, fallback: "Kayıtlı Rapor Dosyaları"),
                meta: reportArchiveMeta,
                icon: "archivebox",
                isExpanded: $isStoredReportsExpanded
            )

            if isStoredReportsExpanded {
                if let reportsLoadError {
                    ReportArchiveStateCard(
                        icon: "exclamationmark.triangle.fill",
                        title: RDLocalization.string("reports.report.view.arsiv.yuklenemedi.e3e4016e", table: .reports, fallback: "Arşiv yüklenemedi"),
                        subtitle: reportsLoadError,
                        tint: Color.rdCriticalText,
                        actionTitle: RDLocalization.string("reports.report.view.tekrar.dene.84b0ba25", table: .reports, fallback: "Tekrar dene")
                    ) {
                        Task { await loadReports() }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if storedReports.isEmpty {
                    ReportArchiveStateCard(
                        icon: "tray",
                        title: RDLocalization.string("reports.report.view.henuz.kayitli.rapor.yok.d61ba3c3", table: .reports, fallback: "Henüz kayıtlı rapor yok"),
                        subtitle: RDLocalization.string("reports.report.view.pdf.veya.excel.olusturdugunda.dosya.rapor.arsivi.a24e418b", table: .reports, fallback: "PDF veya Excel oluşturduğunda dosya rapor arşivine kaydedilecek."),
                        tint: Color.rdSlate
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    VStack(spacing: 7) {
                        reportArchiveControls

                        if filteredStoredReports.isEmpty {
                            ReportArchiveStateCard(
                                icon: "magnifyingglass",
                                title: RDLocalization.string("reports.report.view.eslesen.rapor.yok.02b01d44", table: .reports, fallback: "Eşleşen rapor yok"),
                                subtitle: RDLocalization.string("reports.report.view.arama.veya.filtreyi.degistirerek.arsivdeki.diger.1027ecf1", table: .reports, fallback: "Arama veya filtreyi değiştirerek arşivdeki diğer dosyaları görebilirsin."),
                                tint: Color.rdSlate,
                                actionTitle: RDLocalization.string("reports.report.view.filtreleri.temizle.366d1edd", table: .reports, fallback: "Filtreleri temizle")
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
        .background(reportCardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(reportCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .reportCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isStoredReportsExpanded)
    }

    private var reportArchiveControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(NovaFont.font(.body))
                        .foregroundStyle(Color.rdSlate)

                    TextField(RDLocalization.string("reports.report.view.rapor.ara.1e3bedc8", table: .reports, fallback: "Rapor ara"), text: $reportSearch)
                        .font(NovaFont.font(.body))
                        .foregroundStyle(Color.rdBlack)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("report.archive.search")

                    if !reportSearch.isEmpty {
                        Button {
                            reportSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(NovaFont.font(.body))
                                .foregroundStyle(Color.rdSlate.opacity(0.72))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(RDLocalization.string("reports.report.view.aramayi.temizle.7b76195f", table: .reports, fallback: "Aramayı temizle"))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(reportInsetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(reportCardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if app.currentTier.isPaid {
                    Button {
                        showCompanyFilter = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: selectedCompanyFilter == nil ? "building.2" : "building.2.fill")
                            .font(NovaFont.font(.cardTitle))
                            .foregroundStyle(selectedCompanyFilter == nil ? Color.rdBlack : Color.rdGreenDark)
                            .frame(width: 40, height: 40)
                            .background(selectedCompanyFilter == nil ? reportInsetFill : Color.rdGreenSoft)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedCompanyFilter == nil ? reportCardBorder : Color.rdGreen.opacity(0.32), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(RDPressableButtonStyle())
                    .accessibilityLabel(RDLocalization.string("reports.report.view.firma.filtresi.e7be67fb", table: .reports, fallback: "Firma filtresi"))
                    .accessibilityIdentifier("report.company_filter")
                }

                if hasActiveReportArchiveFilters {
                    Button {
                        clearReportArchiveFilters()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(NovaFont.font(.cardTitle))
                            .foregroundStyle(Color.rdGreen)
                            .frame(width: 40, height: 40)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(RDPressableButtonStyle())
                    .accessibilityLabel(RDLocalization.string("reports.report.view.rapor.filtrelerini.temizle.780a1485", table: .reports, fallback: "Rapor filtrelerini temizle"))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportArchiveFilter.allCases) { filter in
                        ReportArchiveFilterChip(
                            title: filter.title,
                            accessibilityIdentifier: "report.archive.filter.\(filter.rawValue)",
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
        .background(colorScheme == .dark ? Color(hex: "#111615") : Color.rdFog.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(reportCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .reportCardDepth(colorScheme: colorScheme, radius: 3.5, x: 4, y: 5)
    }

    private var analysisSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            collapsibleSectionTitle(
                RDLocalization.string("reports.report.view.rapora.donustur.dc554fbf", table: .reports, fallback: "Rapora Dönüştür"),
                meta: RDLocalization.format("reports.report.view.1.analiz.d9311dde", table: .reports, fallback: "%1$@ analiz", arguments: [String(describing: analyses.count)]),
                icon: "wand.and.stars",
                isExpanded: $isAnalysisSelectorExpanded
            )

            if isAnalysisSelectorExpanded {
                if analyses.isEmpty {
                    ReportEmptyInlineCard(
                        icon: "doc.text.magnifyingglass",
                        title: RDLocalization.string("reports.report.view.rapor.kaynagi.bekleniyor.1ad81b3e", table: .reports, fallback: "Rapor kaynağı bekleniyor"),
                        subtitle: RDLocalization.string("reports.report.view.analiz.tamamlandiginda.burada.standart.rapor.vey.db4ef1d2", table: .reports, fallback: "Analiz tamamlandığında burada Standart Rapor veya Pro Risk Analizi üretebilirsin.")
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
        .background(reportCardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(reportCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .reportCardDepth(colorScheme: colorScheme, radius: 4, x: 5, y: 6)
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
                    .font(NovaFont.font(.body))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 30, height: 30)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(title)
                    .font(NovaFont.font(.cardTitle))
                    .foregroundStyle(Color.rdBlack)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Text(meta)
                    .rdMono(size: 11, weight: .semibold)
                    .foregroundStyle(reportMetaText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(reportInsetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Image(systemName: "chevron.down")
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(reportMetaText)
                    .frame(width: 28, height: 28)
                    .background(reportInsetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
            }
            .padding(2)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(isExpanded.wrappedValue ? RDLocalization.string("reports.report.view.bolumu.kapatir.c58a1796", table: .reports, fallback: "Bölümü kapatır") : RDLocalization.string("reports.report.view.bolumu.acar.6e2c5db7", table: .reports, fallback: "Bölümü açar"))
    }

    private var riskReportCount: Int {
        storedReports.filter(\.isRiskAnalysisReport).count
    }

    private var reportArchiveMeta: String {
        if reportsLoadError != nil, storedReports.isEmpty {
            return "hata"
        }
        if storedReports.isEmpty || filteredStoredReports.count == storedReports.count {
            return RDLocalization.plural(
                "reports.count.files",
                table: .reports,
                value: storedReports.count,
                fallbackOne: "%lld dosya",
                fallbackOther: "%lld dosya"
            )
        }
        return "\(filteredStoredReports.count)/\(storedReports.count)"
    }

    private var filteredStoredReports: [ReportRow] {
        let needle = normalizedReportSearch(reportSearch)
        return storedReports.filter { report in
            let matchesSearch = needle.isEmpty || normalizedReportSearch(reportSearchText(for: report)).contains(needle)
            let matchesCompany = selectedCompanyFilter == nil ||
                report.companyID == selectedCompanyFilter?.id ||
                report.companySnapshot?.id == selectedCompanyFilter?.id
            return matchesSearch && matchesReportFilter(report) && matchesCompany
        }
    }

    private var visibleStoredReports: [ReportRow] {
        Array(filteredStoredReports.prefix(visibleReportCount))
    }

    private var hasActiveReportArchiveFilters: Bool {
        !reportSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reportFilter != .all
            || selectedCompanyFilter != nil
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
                    Text(RDLocalization.string("reports.report.view.rapor.verileri.hazirlaniyor.c052fd0a", table: .reports, fallback: "Rapor verileri hazırlanıyor"))
                        .font(NovaFont.font(.cardTitle))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("reports.report.view.son.tamamlanan.analizler.getiriliyor.8dd7d1d4", table: .reports, fallback: "Son tamamlanan analizler getiriliyor."))
                        .font(NovaFont.font(.body))
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
                    .font(RDTypography.font(size: RDFontScale.size(28), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 52, height: 52)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(RDLocalization.string("reports.report.view.henuz.raporlanacak.analiz.yok.ff3a933e", table: .reports, fallback: "Henüz raporlanacak analiz yok"))
                        .font(NovaFont.font(.screenTitle))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("reports.report.view.fotograf.analizi.tamamlandiginda.rapor.onizlemes.960da4ed", table: .reports, fallback: "Fotoğraf analizi tamamlandığında rapor önizlemesi burada gerçek bulgularla oluşacak."))
                        .font(NovaFont.font(.body))
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
            report.createdAt ?? "",
            report.companySnapshot?.name ?? "",
            report.companySnapshot?.hazardClass.title ?? ""
        ].joined(separator: " ")
    }

    private func normalizedReportSearch(_ value: String) -> String {
        value
            .lowercased(with: .autoupdatingCurrent)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .autoupdatingCurrent)
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
                    offset: offset,
                    photoAnalysesOnly: true
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
                        context: RDLocalization.string(
                            "reports.report.view.rapor.arsivi.yuklenemedi.8c44ed8d",
                            table: .reports,
                            fallback: "Rapor arşivi yüklenemedi"
                        ),
                        fallbackTitle: RDLocalization.string("reports.report.view.rapor.arsivi.yuklenemedi.8c44ed8d", table: .reports, fallback: "Rapor arşivi yüklenemedi")
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
            selectedCompanyFilter = nil
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
        #if DEBUG
        if Self.usesUITestReportFixtures {
            let company = Self.uiTestCompany
            companies = [company]
            storedReports = [Self.uiTestReport(company: company)]
            updateFreeRiskAnalysisTrialStateFromCachedReports()
            analyses = [Self.uiTestAnalysis]
            selectedBundle = nil
            selectedID = nil
            reportsLoadError = nil
            canLoadMoreStoredReports = false
            isLoadingMoreStoredReports = false
            isStoredReportsExpanded = true
            isAnalysisSelectorExpanded = true
            return
        }
        #endif

        guard app.auth.session != nil else {
            analyses = []
            storedReports = []
            updateFreeRiskAnalysisTrialStateFromCachedReports()
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
            async let reportRows = AnalysisService.shared.listReports(
                limit: reportArchiveFetchPageSize,
                photoAnalysesOnly: true
            )
            async let companyRows: [Company] = app.currentTier.isPaid
                ? CompanyService.shared.listCompanies(includeArchived: true)
                : []
            let rows = try await analysisRows
            companies = (try? await companyRows) ?? []
            do {
                let reports = try await reportRows
                storedReports = reports
                updateFreeRiskAnalysisTrialStateFromCachedReports()
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
                    context: RDLocalization.string("reports.report.view.rapor.arsivi.yuklenemedi.7fec88c0", table: .reports, fallback: "Rapor arşivi yüklenemedi"),
                    fallbackTitle: RDLocalization.string("reports.report.view.rapor.arsivi.yuklenemedi.b30846fc", table: .reports, fallback: "Rapor arşivi yüklenemedi")
                ).fullText
                storedReports = []
                updateFreeRiskAnalysisTrialStateFromCachedReports()
                canLoadMoreStoredReports = false
            }
            visibleReportCount = min(visibleReportCount, max(filteredStoredReports.count, reportArchivePageSize))
            analyses = rows
            selectedBundle = nil
            selectedID = nil
        } catch {
            errorMessage = AppErrorMessage.make(error, context: RDLocalization.string("reports.report.view.raporlar.yuklenemedi.6bb44aa9", table: .reports, fallback: "Raporlar yüklenemedi"), fallbackTitle: RDLocalization.string("reports.report.view.raporlar.yuklenemedi.e5c73c2a", table: .reports, fallback: "Raporlar yüklenemedi")).fullText
            analyses = []
            storedReports = []
            updateFreeRiskAnalysisTrialStateFromCachedReports()
            selectedBundle = nil
            selectedID = nil
            reportsLoadError = nil
            canLoadMoreStoredReports = false
            isLoadingMoreStoredReports = false
        }
    }

    #if DEBUG
    private static var usesUITestReportFixtures: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_REPORT_FIXTURES")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_REPORT_FIXTURES"] == "1"
    }

    private static var uiTestCompany: Company {
        Company(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000c001")!,
            userID: Self.uiTestUserID,
            name: RDLocalization.string("reports.report.view.test.aktif.firma.5d72481d", table: .reports, fallback: "Aktif Test Firması"),
            hazardClass: .high,
            logoPath: nil,
            address: RDLocalization.string("reports.report.view.test.mah.guvenlik.cad.no.10.035c5225", table: .reports, fallback: "Test Mah. Güvenlik Cad. No: 10"),
            contactPerson: RDLocalization.string("reports.report.view.ayse.denetim.6dcaaaf4", table: .reports, fallback: "Ayşe Denetim"),
            department: RDLocalization.string("reports.report.view.bakim.ekibi.56eec922", table: .reports, fallback: "Bakım Ekibi"),
            defaultResponsible: RDLocalization.string("reports.report.view.saha.sefi.8c568787", table: .reports, fallback: "Saha Şefi"),
            defaultDueDays: 30,
            isArchived: false,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private static var uiTestUserID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!
    }

    private static func uiTestReport(company: Company) -> ReportRow {
        ReportRow(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000a101")!,
            userID: company.userID,
            analysisID: UUID(uuidString: "00000000-0000-0000-0000-00000000a001")!,
            companyID: company.id,
            companySnapshot: CompanySnapshot(company: company),
            format: "pdf",
            kind: "standard",
            method: "fine_kinney",
            title: RDLocalization.string("reports.report.view.test.firma.raporu.283009de", table: .reports, fallback: "Test Firma Raporu"),
            storagePath: "ui-test/reports/test-firma-raporu.pdf",
            fileName: "test-firma-raporu.pdf",
            mimeType: "application/pdf",
            fileSize: 128_000,
            requestID: nil,
            supportID: nil,
            createdAt: "2026-05-28T00:00:00Z"
        )
    }

    private static var uiTestAnalysis: AnalysisRow {
        var analysis = AnalysisRow(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000a201")!,
            userID: Self.uiTestUserID,
            companyID: Self.uiTestCompany.id,
            title: RDLocalization.string("reports.report.view.ui.test.rapor.kaynagi.cfdd432a", table: .reports, fallback: "UI Test Rapor Kaynağı"),
            kind: "photo",
            canvas: "general",
            status: "completed",
            statusMessage: nil,
            aiSummary: RDLocalization.string("reports.report.view.ui.test.rapor.olusturma.akisi.icin.fixture.anali.4de1fbd3", table: .reports, fallback: "UI test rapor oluşturma akışı için fixture analiz."),
            totalScoreFK: 1_920,
            totalScoreM5: 62,
            highestBandFK: RiskLevel.critical.rawValue,
            highestBandM5: RiskLevel.critical.rawValue,
            findingCount: Finding.mock.count,
            createdAt: "2026-05-28T00:00:00Z",
            analysisSector: nil,
            analysisSectorSource: nil,
            analysisSectorPromptVersion: nil
        )
        let fixtureLanguage = RDLanguage.current
        analysis.outputLanguage = fixtureLanguage.rawValue
        analysis.outputLocale = fixtureLanguage == .english ? "en-GB" : "tr-TR"
        analysis.workJurisdictionCountry = fixtureLanguage == .english ? "ZZ" : "TR"
        analysis.safetyProfileID = fixtureLanguage == .english
            ? "english_international_generic_v1"
            : "turkey_current_v1"
        analysis.safetyProfileVersion = 1
        analysis.localizationSnapshot = RDAnalysisLocalizationSnapshot(
            schemaVersion: 1,
            outputLanguage: analysis.outputLanguage,
            outputLocale: analysis.outputLocale,
            workJurisdictionCountry: analysis.workJurisdictionCountry,
            workJurisdictionRegion: nil,
            safetyProfileID: analysis.safetyProfileID,
            safetyProfileVersion: analysis.safetyProfileVersion,
            structuredRegulatoryReferencesEnabled: fixtureLanguage == .turkish
        )
        return analysis
    }
    #endif

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
                let bundle = try await AnalysisService.shared.result(analysisID: row.id)
                selectedBundle = bundle
                selectedReportCompany = await company(for: bundle.analysis.companyID)
                var sourceOptions = defaultReportOptions(
                    kind: reportOptions.kind == .standard
                        ? .riskAnalysis
                        : reportOptions.kind
                )
                sourceOptions.language = bundle.analysis.resolvedOutputLanguage
                reportOptions = resolvedReportOptions(
                    sourceOptions,
                    company: selectedReportCompany
                )
                await app.refreshPlanState()
                _ = await refreshReportQuotaState()
                await refreshFreeRiskAnalysisTrialState()
                _ = try? await loadProfileLogoIfNeeded()
                showSourceReportSheet = true
            } catch {
                errorMessage = AppErrorMessage.make(error, context: RDLocalization.string("reports.report.view.analiz.rapora.acilamadi.40a7b44c", table: .reports, fallback: "Analiz rapora açılamadı"), fallbackTitle: RDLocalization.string("reports.report.view.analiz.rapora.acilamadi.b9df7a3d", table: .reports, fallback: "Analiz rapora açılamadı")).fullText
            }
            loadingID = nil
        }
    }

    private func generateSelectedReport(options: PDFReportOptions? = nil, companyLogo: UIImage? = nil) {
        guard !pdfGeneration.isActive else { return }
        guard let selectedBundle else {
            errorMessage = AppErrorMessage.make(
                AnalysisService.AnalysisError.invalidInput(
                    RDLocalization.string(
                        "reports.report.view.pdf.olusturmak.icin.tamamlanmis.bir.analiz.secme.021600c5",
                        table: .reports,
                        fallback: "PDF oluşturmak için tamamlanmış bir analiz seçmelisin."
                    )
                ),
                context: RDLocalization.string(
                    "reports.report.view.pdf.olusturulamadi.ff617364",
                    table: .reports,
                    fallback: "PDF oluşturulamadı"
                ),
                fallbackTitle: RDLocalization.string("reports.report.view.pdf.olusturulamadi.ff617364", table: .reports, fallback: "PDF oluşturulamadı")
            ).fullText
            return
        }
        #if DEBUG
        let fallbackUITestUserID = Self.usesUITestReportFixtures ? Self.uiTestUserID : nil
        #else
        let fallbackUITestUserID: UUID? = nil
        #endif
        guard let userID = app.auth.session?.user.id ?? fallbackUITestUserID else {
            errorMessage = AppErrorMessage.make(AnalysisService.AnalysisError.notAuthenticated, context: RDLocalization.string("reports.report.view.rapor.kaydedilemedi.ad69953f", table: .reports, fallback: "Rapor kaydedilemedi")).fullText
            return
        }

        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        pdfGeneration.start()
        Task {
            do {
                let company = selectedReportCompany
                let resolvedOptions = resolvedReportOptions(options ?? defaultReportOptions(kind: .standard), company: company)
                if resolvedOptions.kind == .riskAnalysis,
                   await riskAnalysisTrialExhaustedBeforeGeneration() {
                    pdfGeneration.stop()
                    return
                }
                if !shouldBypassReportQuota(for: resolvedOptions),
                   await refreshReportQuotaState() {
                    pdfGeneration.stop()
                    reportOptions.kind = .standard
                    showSourceReportSheet = true
                    return
                }
                let reportImages = try await loadReportImages(for: selectedBundle)
                pdfGeneration.advance(to: 0.23)
                let resolvedLogo = await resolveReportLogo(
                    company: company,
                    fallbackLogo: companyLogo
                )
                let input = PDFReportService.ReportInput(
                    bundle: selectedBundle,
                    findings: sortedFindings(selectedBundle.findings.map(\.asFinding), method: resolvedOptions.method),
                    profile: app.profile,
                    images: reportImages,
                    companyLogo: resolvedLogo,
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
                        company: company,
                        requestID: requestID,
                        supportID: supportID
                    )
                    try await backfillAnalysisCompanyIfNeeded(bundle: selectedBundle, company: company)
                    mergeStoredReport(report)
                } catch {
                    Self.logger.error("Report archive failed after PDF generation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    if AppErrorMessage.isReportQuotaExceeded(error.localizedDescription) {
                        throw error
                    } else {
                        archiveWarning = AppErrorMessage.make(
                            rawMessage: RDLocalization.format("reports.report.view.1.destek.kodu.2.530c2aa3", table: .reports, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: error.localizedDescription), String(describing: supportID)]),
                            context: RDLocalization.string("reports.report.view.rapor.arsive.kaydedilemedi.a5342f5d", table: .reports, fallback: "Rapor arşive kaydedilemedi"),
                            fallbackTitle: RDLocalization.string("reports.report.view.rapor.arsive.kaydedilemedi.0af90984", table: .reports, fallback: "Rapor arşive kaydedilemedi")
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
                    rawMessage: RDLocalization.format("reports.report.view.1.destek.kodu.2.530c2aa3", table: .reports, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: error.localizedDescription), String(describing: supportID)]),
                    context: RDLocalization.string("reports.report.view.pdf.olusturulamadi.95f69251", table: .reports, fallback: "PDF oluşturulamadı"),
                    fallbackTitle: RDLocalization.string("reports.report.view.pdf.olusturulamadi.fd9b8c6f", table: .reports, fallback: "PDF oluşturulamadı")
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
                let resolvedOptions = resolvedReportOptions(reportOptions, company: selectedReportCompany)
                if await riskAnalysisTrialExhaustedBeforeGeneration() {
                    excelGenerationID = nil
                    return
                }
                if !shouldBypassReportQuota(for: resolvedOptions),
                   await refreshReportQuotaState() {
                    reportOptions.kind = .standard
                    showSourceReportSheet = true
                    excelGenerationID = nil
                    return
                }
                let report = try await AnalysisService.shared.generateExcelReport(
                    analysisID: selectedBundle.analysis.id,
                    method: reportOptions.method,
                    language: reportOptions.language,
                    companyID: selectedReportCompany?.id,
                    requestID: requestID,
                    supportID: supportID
                )
                try await backfillAnalysisCompanyIfNeeded(bundle: selectedBundle, company: selectedReportCompany)
                mergeStoredReport(report)
                let url = try await AnalysisService.shared.reportFileURL(
                    for: report,
                    requestID: requestID,
                    supportID: supportID,
                    source: .reportsArchive
                )
                shareItem = ShareItem(url: url)
            } catch {
                if handleReportQuotaIfNeeded(error) {
                    excelGenerationID = nil
                    return
                }
                errorMessage = AppErrorMessage.make(
                    rawMessage: RDLocalization.format("reports.report.view.1.destek.kodu.2.530c2aa3", table: .reports, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: error.localizedDescription), String(describing: supportID)]),
                    context: RDLocalization.string("reports.report.view.excel.olusturulamadi.3590499c", table: .reports, fallback: "Excel oluşturulamadı"),
                    fallbackTitle: RDLocalization.string("reports.report.view.excel.olusturulamadi.81e5ab89", table: .reports, fallback: "Excel oluşturulamadı")
                ).fullText
            }
            excelGenerationID = nil
        }
    }

    private func mergeStoredReport(_ report: ReportRow) {
        reportsLoadError = nil
        storedReports.removeAll { $0.id == report.id || $0.storagePath == report.storagePath }
        storedReports.insert(report, at: 0)
        if report.usesRiskAnalysisTrial {
            freeRiskAnalysisTrialUsed = true
        }
        visibleReportCount = max(visibleReportCount, min(filteredStoredReports.count, reportArchivePageSize))
    }

    private func appendStoredReports(_ reports: [ReportRow]) {
        guard !reports.isEmpty else { return }
        let existingIDs = Set(storedReports.map(\.id))
        let existingPaths = Set(storedReports.map(\.storagePath))
        let uniqueReports = reports.filter { !existingIDs.contains($0.id) && !existingPaths.contains($0.storagePath) }
        storedReports.append(contentsOf: uniqueReports)
        updateFreeRiskAnalysisTrialStateFromCachedReports()
    }

    @discardableResult
    private func handleReportQuotaIfNeeded(_ error: Error) -> Bool {
        if AppErrorMessage.isFreeRiskAnalysisTrialExhausted(error.localizedDescription) {
            freeRiskAnalysisTrialUsed = true
            reportQuotaExhausted = false
            reportOptions.kind = .standard
            showSourceReportSheet = true
            return true
        }
        guard AppErrorMessage.isReportQuotaExceeded(error.localizedDescription) else { return false }
        reportQuotaExhausted = true
        reportOptions.kind = .standard
        showSourceReportSheet = true
        return true
    }

    private func refreshReportQuotaState() async -> Bool {
        do {
            let usage = try await AnalysisService.shared.monthlyReportQuotaUsage(tier: app.currentTier)
            reportQuotaExhausted = usage.isExhausted
        } catch {
            reportQuotaExhausted = false
        }
        return reportQuotaExhausted
    }

    private func updateFreeRiskAnalysisTrialStateFromCachedReports() {
        freeRiskAnalysisTrialUsed = storedReports.contains { $0.usesRiskAnalysisTrial }
    }

    private func refreshFreeRiskAnalysisTrialState() async {
        guard app.currentTier == .free else {
            freeRiskAnalysisTrialUsed = false
            return
        }
        do {
            let usage = try await AnalysisService.shared.freeRiskAnalysisTrialUsage()
            freeRiskAnalysisTrialUsed = usage.isExhausted
        } catch {
            updateFreeRiskAnalysisTrialStateFromCachedReports()
        }
    }

    private func shouldBypassReportQuota(for options: PDFReportOptions) -> Bool {
        app.currentTier == .free && options.kind == .riskAnalysis && !freeRiskAnalysisTrialUsed
    }

    private func riskAnalysisTrialExhaustedBeforeGeneration() async -> Bool {
        guard app.currentTier == .free else { return false }
        await refreshFreeRiskAnalysisTrialState()
        guard freeRiskAnalysisTrialUsed else { return false }
        reportOptions.kind = .standard
        showSourceReportSheet = true
        errorMessage = AppErrorMessage.make(
            rawMessage: "free_risk_analysis_trial_exhausted:1/1",
            context: RDLocalization.string("reports.report.view.risk.analizi.tablosu.olusturulamadi.4e97001c", table: .reports, fallback: "Risk analizi tablosu oluşturulamadı"),
            fallbackTitle: RDLocalization.string("reports.report.view.risk.analizi.tablosu.olusturulamadi.156552f0", table: .reports, fallback: "Risk analizi tablosu oluşturulamadı")
        ).fullText
        return true
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
                    supportID: supportID,
                    source: .reportsArchive
                )
                shareItem = ShareItem(url: url)
            } catch {
                errorMessage = AppErrorMessage.make(
                    rawMessage: RDLocalization.format("reports.report.view.1.destek.kodu.2.530c2aa3", table: .reports, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: error.localizedDescription), String(describing: supportID)]),
                    context: RDLocalization.string("reports.report.view.rapor.indirilemedi.c2e21361", table: .reports, fallback: "Rapor indirilemedi"),
                    fallbackTitle: RDLocalization.string("reports.report.view.rapor.indirilemedi.3fc8490a", table: .reports, fallback: "Rapor indirilemedi")
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
                    rawMessage: RDLocalization.format("reports.report.view.1.destek.kodu.2.530c2aa3", table: .reports, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: error.localizedDescription), String(describing: supportID)]),
                    context: RDLocalization.string("reports.report.view.rapor.silinemedi.4121267d", table: .reports, fallback: "Rapor silinemedi"),
                    fallbackTitle: RDLocalization.string("reports.report.view.rapor.silinemedi.798148fd", table: .reports, fallback: "Rapor silinemedi")
                ).fullText
            }
            deletingReportID = nil
        }
    }

    private func loadReportImages(for bundle: AnalysisResultBundle) async throws -> [UIImage] {
        var images: [UIImage] = []
        let photoRows = bundle.photos.sorted { left, right in
            switch (left.sequenceIndex, right.sequenceIndex) {
            case let (leftIndex?, rightIndex?) where leftIndex != rightIndex:
                return leftIndex < rightIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return left.storagePath < right.storagePath
            }
        }
        images.reserveCapacity(photoRows.count)
        for row in photoRows {
            let data = try await AnalysisService.shared.photoData(path: row.storagePath)
            guard let image = UIImage(data: data) else {
                throw AnalysisService.AnalysisError.storageFailed(RDLocalization.string("reports.report.view.analiz.fotografi.indirildi.ancak.goruntu.formati.d5768151", table: .reports, fallback: "Analiz fotoğrafı indirildi ancak görüntü formatı açılamadı."))
            }
            images.append(image)
        }
        return images
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
            companyID: nil,
            language: app.languagePreference
        )
    }

    private func resolvedReportOptions(_ options: PDFReportOptions, company: Company?) -> PDFReportOptions {
        guard let company else { return options }
        var resolved = options
        resolved.companyID = company.id
        if resolved.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved.companyName = company.name
        }
        if resolved.companyInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved.companyInfo = company.reportInfoText
        }
        return resolved
    }

    private func backfillAnalysisCompanyIfNeeded(bundle: AnalysisResultBundle, company: Company?) async throws {
        guard let company, bundle.analysis.companyID == nil else { return }
        try await AnalysisService.shared.assignCompany(to: bundle.analysis.id, companyID: company.id)
    }

    private func company(for companyID: UUID?) async -> Company? {
        guard let companyID, app.currentTier.isPaid else { return nil }
        do {
            let companies = try await CompanyService.shared.listCompanies(includeArchived: true)
            return companies.first { $0.id == companyID }
        } catch {
            return nil
        }
    }

    @discardableResult
    private func loadProfileLogoIfNeeded() async throws -> UIImage? {
        if let profileReportLogo { return profileReportLogo }
        guard let path = app.profile?.companyLogoURL, !path.isEmpty else { return nil }
        let image = try await app.auth.profileLogoImage(path: path)
        await MainActor.run {
            profileReportLogo = image
        }
        return image
    }

    private func resolveReportLogo(company: Company?, fallbackLogo: UIImage?) async -> UIImage? {
        if let companyLogo = await loadCompanyLogoIfAvailable(for: company) {
            return companyLogo
        }
        if let fallbackLogo {
            return fallbackLogo
        }
        return await loadProfileLogoIfAvailable()
    }

    private func loadCompanyLogoIfAvailable(for company: Company?) async -> UIImage? {
        guard let path = company?.logoPath, !path.isEmpty else { return nil }
        do {
            return try await CompanyService.shared.logoImage(path: path)
        } catch {
            Self.logger.warning("Company logo unavailable for report fallback: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func loadProfileLogoIfAvailable() async -> UIImage? {
        do {
            return try await loadProfileLogoIfNeeded()
        } catch {
            Self.logger.warning("Profile logo unavailable for report fallback: \(error.localizedDescription, privacy: .public)")
            return nil
        }
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
                    .font(NovaFont.font(.meta))
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
                Text(RDLocalization.string("reports.report.view.is.guvenligi.risk.analizi.18db139d", table: .reports, fallback: "İş Güvenliği Risk Analizi"))
                    .font(NovaFont.font(.screenTitle))
                    .tracking(-0.3)
                    .foregroundStyle(Color.rdBlack)
                Text("\(analysis.title) · \(canvasLabel)")
                    .font(NovaFont.font(.meta))
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
                Text(RDLocalization.format("reports.report.view.1.bulgu.raporun.devaminda.d7f885e4", table: .reports, fallback: "+ %1$@ bulgu raporun devamında", arguments: [String(describing: findings.count - 6)]))
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
                .font(NovaFont.font(.screenTitle))
                .foregroundStyle(Color.rdLow)
            VStack(alignment: .leading, spacing: 3) {
                Text(RDLocalization.string("reports.report.view.tehlike.tespit.edilmedi.69a999af", table: .reports, fallback: "Tehlike tespit edilmedi"))
                    .font(NovaFont.font(.body))
                    .foregroundStyle(Color.rdBlack)
                Text(RDLocalization.string("reports.report.view.bu.analiz.icin.ai.bulgu.kaydi.donmedi.8e37f5b1", table: .reports, fallback: "Bu analiz için AI bulgu kaydı dönmedi."))
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdLowBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        Text(RDLocalization.format("reports.report.view.sayfa.1.1.isg.uzmani.2.3.14375cf7", table: .reports, fallback: "Sayfa 1 / %1$@ · İSG Uzmanı: %2$@ · %3$@", arguments: [String(describing: max(Int(ceil(Double(max(findings.count, 1)) / 6.0)), 1)), String(describing: expertName), String(describing: expertCredential)]))
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
                .font(NovaFont.font(.meta))
                .foregroundStyle(level.textColor)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level.bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text(RDLocalization.string("reports.report.view.copy.9fbd915a", table: .reports, fallback: "#")).frame(width: 20, alignment: .leading)
            Text(RDLocalization.string("reports.report.view.risk.3424dae6", table: .reports, fallback: "RİSK")).frame(maxWidth: .infinity, alignment: .leading)
            Text(RDLocalization.string("reports.report.view.fk.a594f58b", table: .reports, fallback: "FK")).frame(width: 48, alignment: .leading)
            Text(RDLocalization.string("reports.report.view.5.5.fcdf178d", table: .reports, fallback: "5×5")).frame(width: 44, alignment: .leading)
        }
        .font(NovaFont.font(.meta))
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
                Text(finding.displayTitle)
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(2)
                Text(finding.category)
                    .font(NovaFont.font(.meta))
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
        guard let date = analysis.createdAt.flatMap(Self.parseDate) else { return RDLocalization.string("reports.report.view.tarih.yok.b95f2b1f", table: .reports, fallback: "Tarih yok") }
        let formatter = DateFormatter()
        formatter.locale = analysis.resolvedOutputLanguage.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var documentNo: String {
        String(analysis.id.uuidString.prefix(8)).uppercased()
    }

    private var methodSummary: String {
        RDLocalization.format("reports.report.view.fine.kinney.toplam.1.5.5.toplam.2.24785862", table: .reports, fallback: "Fine-Kinney toplamı: %1$@ · 5×5 toplam: %2$@", arguments: [String(describing: scoreText(analysis.totalScoreFK ?? 0)), String(describing: analysis.totalScoreM5 ?? 0)])
    }

    private var expertName: String {
        profile?.displayName ?? RDLocalization.string("reports.report.view.kullanici.2fbbc3c4", table: .reports, fallback: "Kullanıcı")
    }

    private var expertCredential: String {
        profile?.certificateNumber ?? profile?.title ?? RDLocalization.string("reports.report.view.isg.uzmani.e760f8b8", table: .reports, fallback: "İSG Uzmanı")
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
    let freeRiskAnalysisTrialRemaining: Int
    let reportQuotaExhausted: Bool
    let isExcelGenerating: Bool
    @ObservedObject var pdfGeneration: PDFGenerationProgressController
    @Binding var reportOptions: PDFReportOptions
    @Binding var selectedCompany: Company?
    @Binding var companyLogo: UIImage?
    let onGenerateCustom: (PDFReportOptions, UIImage?) -> Void
    let onGenerateExcel: () -> Void
    let onPaywall: (ReportSettingsPaywallPlacement) -> Void
    @State private var showSettings = false
    @State private var reportSettingsDetent: PresentationDetent = .medium

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                sheetHeader
                ReportPreview(bundle: bundle, profile: profile)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color.rdCloud)
        .accessibilityIdentifier("report.source_sheet")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            reportActionsBar
        }
        .sheet(isPresented: $showSettings) {
            ReportSettingsSheet(
                options: $reportOptions,
                selectedCompany: $selectedCompany,
                companyLogo: $companyLogo,
                presentationDetent: $reportSettingsDetent,
                profile: profile,
                accessTier: accessTier,
                canUseRiskAnalysis: canUseRiskAnalysis,
                freeRiskAnalysisTrialRemaining: freeRiskAnalysisTrialRemaining,
                reportQuotaExhausted: reportQuotaExhausted,
                onGenerate: {
                    showSettings = false
                    onGenerateCustom(reportOptions, companyLogo)
                },
                onGenerateExcel: {
                    showSettings = false
                    onGenerateExcel()
                },
                onPaywall: { placement in
                    showSettings = false
                    onPaywall(placement)
                },
                onClose: { showSettings = false }
            )
            .presentationDetents([.medium, .large], selection: $reportSettingsDetent)
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
                    .font(NovaFont.font(.body))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 40, height: 40)
                    .background(Color.rdWhite.opacity(0.96))
                    .clipShape(Circle())
                    .shadow(color: Color.rdOnyx.opacity(0.14), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(RDPressableButtonStyle())
            .accessibilityLabel(RDLocalization.string("reports.report.view.pencereyi.kapat.42ff6afc", table: .reports, fallback: "Pencereyi kapat"))
        }
    }

    private var reportActions: some View {
        RDButton(
            title: isExcelGenerating ? RDLocalization.string("reports.report.view.excel.hazirlaniyor.65b62379", table: .reports, fallback: "Excel hazırlanıyor...") : pdfGeneration.isActive ? RDLocalization.string("reports.report.view.rapor.hazirlaniyor.e3f5d393", table: .reports, fallback: "Rapor hazırlanıyor...") : RDLocalization.string("reports.report.view.rapor.olustur.dae645d2", table: .reports, fallback: "Rapor oluştur"),
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
                companyName: selectedCompany?.name ?? profile?.companyName ?? "",
                companyInfo: selectedCompany?.reportInfoText ?? profile?.phone ?? "",
                companyID: selectedCompany?.id,
                language: reportOptions.language
            )
            reportSettingsDetent = .medium
            showSettings = true
        }
        .disabled(isExcelGenerating || pdfGeneration.isActive)
        .accessibilityIdentifier("report.source_sheet.open_settings")
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
                Image(systemName: "camera.viewfinder")
                    .font(NovaFont.font(.cardTitle))
                    .foregroundStyle(level.textColor)
                    .frame(width: 44, height: 44)
                    .background(level.bgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.title)
                            .font(NovaFont.font(.cardTitle))
                            .foregroundStyle(Color.rdBlack)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(level.label)
                            .font(NovaFont.font(.meta))
                            .foregroundStyle(level.textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(level.bgColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(spacing: 6) {
                        Label(dateText, systemImage: "calendar")
                        Text(RDLocalization.string("reports.report.view.copy.4e0b8ebd", table: .reports, fallback: "·"))
                        Text(canvasLabel)
                        Text(RDLocalization.string("reports.report.view.copy.b46dfd10", table: .reports, fallback: "·"))
                        Text(
                            RDLocalization.plural(
                                "reports.count.findings",
                                table: .reports,
                                value: row.findingCount,
                                fallbackOne: "%lld bulgu",
                                fallbackOther: "%lld bulgu"
                            )
                        )
                            .rdMono(size: 12, weight: .semibold)
                    }
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .font(NovaFont.font(.cardTitle))
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
        .accessibilityIdentifier("report.analysis.row.\(row.id.uuidString)")
    }

    private var level: RiskLevel {
        RiskLevel(rawValue: row.highestBandFK ?? row.highestBandM5 ?? "unknown") ?? .unknown
    }

    private var canvasLabel: String {
        AnalysisCanvas.all.first(where: { $0.id == row.canvas })?.title ?? row.canvas.capitalized
    }

    private var dateText: String {
        guard let date = row.createdAt.flatMap(Self.parseDate) else { return RDLocalization.string("reports.report.view.tarih.yok.13758df5", table: .reports, fallback: "Tarih yok") }
        let formatter = DateFormatter()
        formatter.locale = row.resolvedOutputLanguage.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
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
                .font(NovaFont.font(.screenTitle))
                .foregroundStyle(Color.rdSlate)
                .frame(width: 42, height: 42)
                .background(Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(NovaFont.font(.body))
                    .foregroundStyle(Color.rdBlack)
                Text(subtitle)
                    .font(NovaFont.font(.meta))
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
        .reportRowDepth()
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
        case .all: return RDLocalization.string("reports.report.view.tumu.b22778b1", table: .reports, fallback: "Tümü")
        case .pdf: return "PDF"
        case .excel: return RDLocalization.string("reports.report.view.excel.357c12e8", table: .reports, fallback: "excel")
        case .standard: return RDLocalization.string("reports.report.view.standart.6ed5f7d4", table: .reports, fallback: "Standart")
        case .riskAnalysis: return RDLocalization.string("reports.report.view.risk.analizi.873e9b38", table: .reports, fallback: "Risk analizi")
        case .thisWeek: return RDLocalization.string("reports.report.view.bu.hafta.49317c78", table: .reports, fallback: "Bu hafta")
        }
    }
}

private struct ReportArchiveFilterChip: View {
    let title: String
    let accessibilityIdentifier: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(NovaFont.font(.meta))
                }

                Text(title)
                    .font(NovaFont.font(.meta))

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
        .accessibilityLabel(RDLocalization.format("reports.report.view.1.2.rapor.92b1ec5c", table: .reports, fallback: "%1$@, %2$@ rapor", arguments: [String(describing: title), String(describing: count)]))
        .accessibilityIdentifier(accessibilityIdentifier)
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
                .font(NovaFont.font(.screenTitle))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(NovaFont.font(.body))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(NovaFont.font(.meta))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 6) {
                            Image(systemName: actionTitle.localizedCaseInsensitiveContains("tekrar") ? "arrow.clockwise" : "xmark.circle")
                                .font(NovaFont.font(.meta))
                            Text(actionTitle)
                                .font(NovaFont.font(.meta))
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
        .reportRowDepth()
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
                        .font(NovaFont.font(.meta))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.rdGreen)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? RDLocalization.string("reports.report.view.yukleniyor.a5d75bb0", table: .reports, fallback: "Yükleniyor") : hasRemoteMore ? RDLocalization.string("reports.report.view.arsivden.devamini.yukle.c2bc6c86", table: .reports, fallback: "Arşivden devamını yükle") : RDLocalization.string("reports.report.view.daha.fazla.yukle.d1217a26", table: .reports, fallback: "Daha fazla yükle"))
                        .font(NovaFont.font(.body))
                        .foregroundStyle(Color.rdBlack)
                    Text(hasRemoteMore ? RDLocalization.format("reports.report.view.1.eslesen.rapor.gosteriliyor.5d23a465", table: .reports, fallback: "%1$@ eşleşen rapor gösteriliyor", arguments: [String(describing: visibleCount)]) : RDLocalization.format("reports.report.view.1.2.gosteriliyor.dd210f2b", table: .reports, fallback: "%1$@/%2$@ gösteriliyor", arguments: [String(describing: visibleCount), String(describing: totalCount)]))
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
        .reportRowDepth()
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
                    Label(RDLocalization.string("reports.report.view.raporu.sil.2d768ded", table: .reports, fallback: "Raporu sil"), systemImage: "trash")
                }
            }
            .accessibilityAction(named: RDLocalization.string("reports.report.view.raporu.sil.db5653f5", table: .reports, fallback: "Raporu sil")) {
                onDelete()
            }
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(isExcel ? Color(hex: "#EAF1FF") : isRiskAnalysis ? Color.rdGreenSoft : Color.rdFog)
                Image(systemName: iconName)
                    .font(NovaFont.font(.cardTitle))
                    .foregroundStyle(isExcel ? Color(hex: "#2563EB") : isRiskAnalysis ? Color.rdGreen : Color.rdCharcoal)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reportTitle)
                        .font(NovaFont.font(.body))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let titleDateText {
                        Text(titleDateText)
                            .font(NovaFont.font(.meta))
                            .foregroundStyle(Color.rdSlate)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }

                HStack(spacing: 5) {
                    Text(kindLabel)
                        .font(NovaFont.font(.meta))
                        .foregroundStyle(kindStyle.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(kindStyle.background)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .fixedSize(horizontal: true, vertical: false)

                    Text(methodLabel)
                        .rdMono(size: 9.5, weight: .bold)
                        .foregroundStyle(Color.rdCharcoal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.rdFog)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .fixedSize(horizontal: true, vertical: false)

                    Text(statusLabel)
                        .font(NovaFont.font(.meta))
                        .foregroundStyle(statusStyle.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusStyle.background)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .fixedSize(horizontal: true, vertical: false)

                    if let companyLabel {
                        Text(companyLabel)
                            .font(NovaFont.font(.meta))
                            .foregroundStyle(Color.rdGreenDark)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }

                Text(dateText)
                    .font(NovaFont.font(.meta))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading || isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.down.to.line")
                    .font(NovaFont.font(.body))
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 32, height: 32)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isRiskAnalysis ? Color.rdGreen.opacity(0.24) : Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .reportRowDepth()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.archive.row.\(report.id.uuidString)")
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
        if isExcel { return RDLocalization.string("reports.report.view.excel.tablo.6d31e397", table: .reports, fallback: "Excel tablo")  }
        return isRiskAnalysis ? RDLocalization.string("reports.report.view.risk.analizi.9997754e", table: .reports, fallback: "Risk analizi")  : RDLocalization.string("reports.report.view.standart.rapor.380caa82", table: .reports, fallback: "Standart rapor")
    }

    private var kindStyle: (text: Color, background: Color) {
        if isExcel {
            return (Color(hex: "#2563EB"), Color(hex: "#EAF1FF"))
        }
        if isRiskAnalysis {
            return (Color.rdGreen, Color.rdGreenSoft)
        }
        return (Color.rdCharcoal, Color.rdFog)
    }

    private var methodLabel: String {
        if report.method == RiskMethod.matrix5x5.rawValue || report.method == "matrix_5x5" {
            return "5x5"
        }
        return "FK"
    }

    private var statusLabel: String {
        if isDeleting { return RDLocalization.string("reports.report.view.siliniyor.4cf99a12", table: .reports, fallback: "Siliniyor") }
        if isLoading { return RDLocalization.string("reports.report.view.aciliyor.cfcc3a35", table: .reports, fallback: "Açılıyor")  }
        return RDLocalization.string("reports.report.view.hazir.b46b444a", table: .reports, fallback: "Hazır")
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

    private var companyLabel: String? {
        guard let name = report.companySnapshot?.name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return name
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
        guard let date = report.createdAt.flatMap(Self.parseDate) else { return RDLocalization.string("reports.report.view.tarih.yok.204e2241", table: .reports, fallback: "Tarih yok") }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

private extension View {
    func reportCardDepth(
        colorScheme: ColorScheme,
        accent: Color = Color.rdBlack,
        radius: CGFloat = 4,
        x: CGFloat = 5,
        y: CGFloat = 6
    ) -> some View {
        rdCardShadow(colorScheme: colorScheme, accent: accent, radius: radius, x: x, y: y)
    }

    func reportRowDepth() -> some View {
        rdRowShadow()
    }
}

#Preview {
    ReportView()
        .environmentObject(AppState())
}
