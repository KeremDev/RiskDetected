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
    @State private var isGeneratingPDF = false
    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var shareItem: ShareItem?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if isLoading && selectedBundle == nil {
                        loadingCard
                    } else if let selectedBundle {
                        ReportPreview(bundle: selectedBundle, profile: app.profile)
                        reportActions
                        storedReportsSection
                        analysisSelector
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdCloud)
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
    }

    private var header: some View {
        HStack {
            Text("Raporlar")
                .font(.system(size: 30, weight: .bold))
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
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
        }
    }

    private var reportActions: some View {
        HStack(spacing: 8) {
            RDButton(
                title: isGeneratingPDF ? "PDF hazırlanıyor..." : "PDF oluştur",
                style: .secondary,
                icon: isGeneratingPDF ? "hourglass" : "doc.richtext",
                height: 52
            ) {
                generateSelectedReport()
            }
            .disabled(isGeneratingPDF)
                .frame(maxWidth: .infinity)
            RDButton(title: "Paylaş", style: .primary, icon: "square.and.arrow.up", height: 52) {
                generateSelectedReport()
            }
            .disabled(isGeneratingPDF)
                .frame(maxWidth: .infinity)
        }
    }

    private var storedReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("KAYITLI PDF RAPORLAR")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Color.rdSlate)
                Spacer()
                Text("\(storedReports.count) dosya")
                    .rdMono(size: 11, weight: .semibold)
                    .foregroundStyle(Color.rdSlate)
            }

            if storedReports.isEmpty {
                RDCard {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.rdSlate)
                            .frame(width: 36, height: 36)
                            .background(Color.rdFog)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Henüz kayıtlı PDF yok")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.rdBlack)
                            Text("PDF oluşturduğunda dosya Supabase rapor arşivine kaydedilecek.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.rdSlate)
                        }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(storedReports) { report in
                        StoredReportRow(
                            report: report,
                            isLoading: downloadingID == report.id
                        ) {
                            download(report)
                        }
                    }
                }
            }
        }
    }

    private var analysisSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RAPOR KAYNAĞI")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Color.rdSlate)
                Spacer()
                Text("\(analyses.count) analiz")
                    .rdMono(size: 11, weight: .semibold)
                    .foregroundStyle(Color.rdSlate)
            }

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

    private var loadingCard: some View {
        RDCard {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rapor verileri hazırlanıyor")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    Text("Son tamamlanan analizler getiriliyor.")
                        .font(.system(size: 13))
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
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 52, height: 52)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Henüz raporlanacak analiz yok")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    Text("Fotoğraf veya metin analizi tamamlandığında rapor önizlemesi burada gerçek bulgularla oluşacak.")
                        .font(.system(size: 13))
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
            async let reportRows = AnalysisService.shared.listReports(limit: 20)
            let rows = try await analysisRows
            storedReports = (try? await reportRows) ?? []
            analyses = rows

            guard let first = rows.first else {
                selectedBundle = nil
                selectedID = nil
                return
            }

            let targetID = selectedID.flatMap { id in rows.contains(where: { $0.id == id }) ? id : nil } ?? first.id
            selectedID = targetID
            selectedBundle = try await AnalysisService.shared.result(analysisID: targetID)
        } catch {
            errorMessage = error.localizedDescription
            analyses = []
            storedReports = []
            selectedBundle = nil
            selectedID = nil
        }
    }

    private func select(_ row: AnalysisRow) {
        guard row.id != selectedID, loadingID == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedID = row.id
        loadingID = row.id

        Task {
            do {
                selectedBundle = try await AnalysisService.shared.result(analysisID: row.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            loadingID = nil
        }
    }

    private func generateSelectedReport() {
        guard !isGeneratingPDF else { return }
        guard let selectedBundle else {
            errorMessage = "PDF oluşturmak için tamamlanmış bir analiz seçmelisin."
            return
        }
        guard let userID = app.auth.session?.user.id else {
            errorMessage = "Rapor kaydetmek için yeniden giriş yapmalısın."
            return
        }

        isGeneratingPDF = true
        Task {
            do {
                let reportImage = try await loadReportImage(for: selectedBundle)
                let input = PDFReportService.ReportInput(
                    bundle: selectedBundle,
                    findings: selectedBundle.findings.map(\.asFinding),
                    profile: app.profile,
                    image: reportImage,
                    companyLogo: nil,
                    options: PDFReportOptions.standard(method: .fineKinney)
                )
                let url = try PDFReportService.shared.generate(input: input)
                do {
                    _ = try await AnalysisService.shared.storeReport(
                        userID: userID,
                        bundle: selectedBundle,
                        fileURL: url,
                        kind: .standard,
                        method: .fineKinney
                    )
                    storedReports = (try? await AnalysisService.shared.listReports(limit: 20)) ?? storedReports
                } catch {
                    errorMessage = "PDF oluşturuldu ancak rapor arşivine kaydedilemedi: \(error.localizedDescription)"
                }
                shareItem = ShareItem(url: url)
                isGeneratingPDF = false
            } catch {
                errorMessage = error.localizedDescription
                isGeneratingPDF = false
            }
        }
    }

    private func download(_ report: ReportRow) {
        guard downloadingID == nil else { return }
        downloadingID = report.id

        Task {
            do {
                let url = try await AnalysisService.shared.reportFileURL(for: report)
                shareItem = ShareItem(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
            downloadingID = nil
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
}

private struct ReportPreview: View {
    let bundle: AnalysisResultBundle
    let profile: UserProfile?

    private var analysis: AnalysisRow { bundle.analysis }
    private var findings: [Finding] { bundle.findings.map(\.asFinding) }
    private var photoPath: String? { bundle.photos.first?.storagePath }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            reportHeader
            titleBlock
            summaryGrid

            if let summary = analysis.aiSummary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
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
                .fill(Color.rdBlack)
                .frame(height: 2)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("İş Güvenliği Risk Analizi")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.rdBlack)
                Text("\(analysis.title) · \(canvasLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
                Text(methodSummary)
                    .rdMono(size: 10)
                    .foregroundStyle(Color.rdSlate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AnalysisThumbnail(path: photoPath, cornerRadius: 8)
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.rdLow)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tehlike tespit edilmedi")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.rdBlack)
                Text("Bu analiz için AI bulgu kaydı dönmedi.")
                    .font(.system(size: 12))
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
                .font(.system(size: 9, weight: .semibold))
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
        .font(.system(size: 9, weight: .bold))
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(2)
                Text(finding.category)
                    .font(.system(size: 9))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(dateText)
                        Text("·")
                        Text(canvasLabel)
                        Text("·")
                        Text("\(row.findingCount) bulgu")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.title)
                        .font(.system(size: 14, weight: .semibold))
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 16, weight: .semibold))
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
        }
        .buttonStyle(RDPressableButtonStyle())
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
