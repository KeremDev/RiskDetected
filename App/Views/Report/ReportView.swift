import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var app: AppState

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

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
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
        .alert("Rapor Hatası", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showSourceReportSheet) {
            if let selectedBundle {
                ReportSourceSheet(
                    bundle: selectedBundle,
                    profile: app.profile,
                    isPro: app.isPro,
                    pdfGeneration: pdfGeneration,
                    reportOptions: $reportOptions,
                    companyLogo: $reportCompanyLogo,
                    onGenerateStandard: {
                        generateSelectedReport()
                    },
                    onGenerateCustom: { options, logo in
                        generateSelectedReport(options: options, companyLogo: logo)
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
        HStack {
            Text("Raporlar")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(Color.rdBlack)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            RDHeaderAccountCTA {
                showPaywall = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .zIndex(100)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
        }
    }

    private var storedReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Kayıtlı PDF Raporları", meta: "\(storedReports.count) dosya")

            if storedReports.isEmpty {
                RDCard {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .frame(width: 36, height: 36)
                            .background(Color.rdFog)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Henüz kayıtlı PDF yok")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text("PDF oluşturduğunda dosya Supabase rapor arşivine kaydedilecek.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                        }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(storedReports.prefix(visibleReportCount))) { report in
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

                    if visibleReportCount < storedReports.count {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                visibleReportCount = min(visibleReportCount + 5, storedReports.count)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Daha fazla gör")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text("\(min(5, storedReports.count - visibleReportCount)) rapor")
                                    .rdMono(size: 11, weight: .semibold)
                                    .foregroundStyle(Color.rdSlate)
                            }
                            .foregroundStyle(Color.rdBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.rdWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.rdLine, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(RDPressableButtonStyle())
                    }
                }
            }
        }
    }

    private var analysisSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Rapor Kaynağı", meta: "\(analyses.count) analiz")

            VStack(spacing: 8) {
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
        }
    }

    private func sectionTitle(_ title: String, meta: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .multilineTextAlignment(.center)
            Text(meta)
                .rdMono(size: 11, weight: .semibold)
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 2)
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

    private func loadReports() async {
        guard app.auth.session != nil else {
            analyses = []
            storedReports = []
            selectedBundle = nil
            selectedID = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let analysisRows = AnalysisService.shared.listRecent(limit: 12)
            async let reportRows = AnalysisService.shared.listReports(limit: 100)
            let rows = try await analysisRows
            storedReports = (try? await reportRows) ?? []
            visibleReportCount = min(visibleReportCount, max(storedReports.count, 5))
            analyses = rows
            selectedBundle = nil
            selectedID = nil
        } catch {
            errorMessage = AppErrorMessage.make(error, context: "Raporlar yüklenemedi", fallbackTitle: "Raporlar yüklenemedi").fullText
            analyses = []
            storedReports = []
            selectedBundle = nil
            selectedID = nil
        }
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
                do {
                    _ = try await AnalysisService.shared.storeReport(
                        userID: userID,
                        bundle: selectedBundle,
                        fileURL: url,
                        kind: resolvedOptions.kind,
                        method: resolvedOptions.method,
                        requestID: requestID,
                        supportID: supportID
                    )
                    pdfGeneration.advance(to: 0.88)
                    storedReports = (try? await AnalysisService.shared.listReports(limit: 100)) ?? storedReports
                    pdfGeneration.advance(to: 0.94)
                } catch {
                    pdfGeneration.stop()
                    errorMessage = AppErrorMessage.make(
                        rawMessage: "PDF oluşturuldu ancak rapor arşivine kaydedilemedi: \(error.localizedDescription)\nDestek kodu: \(supportID)",
                        context: "Rapor arşive kaydedilemedi",
                        fallbackTitle: "Rapor arşive kaydedilemedi"
                    ).fullText
                    return
                }
                await pdfGeneration.complete()
                shareItem = ShareItem(url: url)
            } catch {
                pdfGeneration.stop()
                errorMessage = AppErrorMessage.make(
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: "PDF oluşturulamadı",
                    fallbackTitle: "PDF oluşturulamadı"
                ).fullText
            }
        }
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
            method: .fineKinney,
            preparedBy: app.profile?.displayName ?? "",
            companyName: app.profile?.companyName ?? ""
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
            Text("GÜVEN").frame(width: 46, alignment: .leading)
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
            Text("\(Int(finding.confidence * 100))%")
                .rdMono(size: 10)
                .foregroundStyle(Color.rdSlate)
                .frame(width: 46, alignment: .leading)
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
    let bundle: AnalysisResultBundle
    let profile: UserProfile?
    let isPro: Bool
    @ObservedObject var pdfGeneration: PDFGenerationProgressController
    @Binding var reportOptions: PDFReportOptions
    @Binding var companyLogo: UIImage?
    let onGenerateStandard: () -> Void
    let onGenerateCustom: (PDFReportOptions, UIImage?) -> Void
    let onPaywall: () -> Void
    @State private var showSettings = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ReportPreview(bundle: bundle, profile: profile)
                reportActions
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color.rdCloud)
        .sheet(isPresented: $showSettings) {
            ReportSettingsSheet(
                options: $reportOptions,
                companyLogo: $companyLogo,
                profile: profile,
                onGenerate: {
                    showSettings = false
                    onGenerateCustom(reportOptions, companyLogo)
                },
                onClose: { showSettings = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var reportActions: some View {
        HStack(spacing: 8) {
            RDButton(
                title: pdfGeneration.isActive ? "PDF hazırlanıyor..." : "PDF oluştur",
                style: .primary,
                icon: pdfGeneration.isActive ? "hourglass" : "doc.richtext",
                height: 52
            ) {
                onGenerateStandard()
            }
            .disabled(pdfGeneration.isActive)
            .frame(maxWidth: .infinity)

            Button {
                if isPro {
                    if reportOptions.kind == .standard {
                        reportOptions = PDFReportOptions(
                            kind: .riskAnalysis,
                            method: .fineKinney,
                            preparedBy: profile?.displayName ?? "",
                            companyName: profile?.companyName ?? ""
                        )
                    }
                    showSettings = true
                } else {
                    onPaywall()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text("Ayarlar")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.rdBlack)
                    .frame(width: 78, height: 52)
                    .background(Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.rdLine, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    RDProBadge(small: true)
                        .scaleEffect(0.72)
                        .offset(x: 9, y: -9)
                }
            }
            .buttonStyle(RDPressableButtonStyle())
        }
    }
}

private struct ReportAnalysisRow: View {
    let row: AnalysisRow
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(dateText)
                        Text("·")
                        Text(canvasLabel)
                        Text("·")
                        Text("\(row.findingCount) bulgu")
                    }
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
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
            .padding(12)
            .background(isSelected ? Color.rdGreenSoft : Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.rdGreen.opacity(0.35) : Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(RDPressableButtonStyle())
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

private struct StoredReportRow: View {
    let report: ReportRow
    let isLoading: Bool
    let isDeleting: Bool
    let action: () -> Void
    let onDelete: () -> Void
    @State private var dragOffset: CGFloat = 0

    private let revealWidth: CGFloat = 74

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                onDelete()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                    dragOffset = 0
                }
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Sil")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: revealWidth, height: 68)
            }
            .background(Color.rdCritical)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(dragOffset < -8 ? 1 : 0)

            rowContent
                .offset(x: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { value in
                            let horizontal = value.translation.width
                            let vertical = abs(value.translation.height)
                            guard abs(horizontal) > vertical else { return }
                            dragOffset = min(0, max(-revealWidth, horizontal))
                        }
                        .onEnded { value in
                            let shouldOpen = value.translation.width < -36
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                                dragOffset = shouldOpen ? -revealWidth : 0
                            }
                        }
                )
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .frame(width: 42, height: 42)
                .background(Color.rdWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(report.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(kindLabel)
                    Text("·")
                    Text(dateText)
                    if let sizeText {
                        Text("·")
                        Text(sizeText)
                    }
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading || isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture {
            if dragOffset < 0 {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                    dragOffset = 0
                }
            } else {
                action()
            }
        }
    }

    private var iconName: String {
        report.kind == PDFReportKind.riskAnalysis.rawValue ? "tablecells" : "doc.richtext"
    }

    private var kindLabel: String {
        report.kind == PDFReportKind.riskAnalysis.rawValue ? "Risk analizi" : "Standart PDF"
    }

    private var sizeText: String? {
        guard let fileSize = report.fileSize else { return nil }
        let kb = max(Int((Double(fileSize) / 1024.0).rounded()), 1)
        return "\(kb) KB"
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
