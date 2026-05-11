import SwiftUI
import UIKit
import PhotosUI
import OSLog

struct ResultView: View {
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "ResultView")

    @EnvironmentObject var app: AppState
    var bundle: AnalysisResultBundle? = nil
    var localPreviewImage: UIImage? = nil
    var onClose: () -> Void = {}
    var onPdf: () -> Void = {}

    private var findings: [Finding] {
        bundle?.findings.map { $0.asFinding } ?? []
    }
    private var sortedFindings: [Finding] {
        findings.sorted {
            let leftBand = $0.band(for: method).level
            let rightBand = $1.band(for: method).level
            let leftRank = rankFor(leftBand)
            let rightRank = rankFor(rightBand)
            if leftRank != rightRank { return leftRank > rightRank }

            let leftScore = $0.score(for: method)
            let rightScore = $1.score(for: method)
            if leftScore != rightScore { return leftScore > rightScore }

            return $0.confidence > $1.confidence
        }
    }
    private var analysisTitle: String {
        bundle?.analysis.title ?? "Analiz Sonucu"
    }
    private var canvasLabel: String {
        let id = bundle?.analysis.canvas ?? "general"
        return AnalysisCanvas.all.first { $0.id == id }?.title ?? id
    }
    private var photoPath: String? {
        bundle?.photos.first?.storagePath
    }

    @State private var method: RiskMethod = .fineKinney
    @State private var selectedFinding: Finding? = nil
    @State private var showPaywall: Bool = false
    @StateObject private var pdfGeneration = PDFGenerationProgressController()
    @State private var isExcelGenerating: Bool = false
    @State private var pdfError: String?
    @State private var shareItem: ShareItem?
    @State private var activityShareItem: ShareItem?
    @State private var showReportSettings: Bool = false
    @State private var reportOptions = PDFReportOptions()
    @State private var reportCompanyLogo: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    photoMetaCard
                    methodSelector
                    methodologySummary
                    if findings.isEmpty {
                        emptyFindingsCard
                    } else {
                        findingsSection
                        if !app.isPro { proUpsellCard }
                        actionButtons
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdPaper)
        .overlay {
            if pdfGeneration.isActive {
                PDFGenerationOverlay(progress: pdfGeneration.progress)
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: pdfGeneration.isActive)
        .sheet(item: $selectedFinding) { finding in
            RiskDetailView(
                finding: finding,
                method: method,
                photoPath: photoPath,
                localPreviewImage: localPreviewImage
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { item in
            DocumentPreview(url: item.url)
        }
        .sheet(item: $activityShareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showReportSettings) {
            ReportSettingsSheet(
                options: $reportOptions,
                companyLogo: $reportCompanyLogo,
                profile: app.profile,
                isPro: app.isPro,
                onGenerate: {
                    showReportSettings = false
                    generateAndSharePDF(options: reportOptions)
                },
                onGenerateExcel: {
                    showReportSettings = false
                    generateAndShareExcel(method: reportOptions.method)
                },
                onPaywall: {
                    showReportSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        showPaywall = true
                    }
                },
                onClose: { showReportSettings = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Rapor Hatası", isPresented: Binding(
            get: { pdfError != nil },
            set: { if !$0 { pdfError = nil } }
        )) {
            Button("Tamam", role: .cancel) { pdfError = nil }
        } message: {
            Text(pdfError ?? "")
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
        }
        .onDisappear {
            pdfGeneration.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack {
                roundIconButton(systemName: "chevron.left", action: onClose)
                Spacer()
            }
            .frame(width: 84)

            Spacer()

            Text("Analiz Sonucu")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Spacer()

            HStack(spacing: 8) {
                roundIconButton(systemName: "arrow.down.to.line") {
                    generateAndSharePDF()
                }
                .accessibilityLabel("Raporu indir")

                roundIconButton(systemName: "square.and.arrow.up") {
                    generateAndSharePDF(presentShareSheet: true)
                }
                .accessibilityLabel("Raporu paylaş")
            }
            .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func roundIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 36, height: 36)
                .foregroundStyle(Color.rdBlack)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.rdWhite)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.rdLine, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    // MARK: - Photo + meta

    private var photoMetaCard: some View {
        RDCard {
            HStack(alignment: .top, spacing: 16) {
                ResultPhotoThumbnail(
                    image: localPreviewImage,
                    path: photoPath,
                    isTextAnalysis: bundle?.analysis.kind == "text",
                    cornerRadius: 12
                )
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(analysisTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(formattedDate) · \(canvasLabel)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(1)
                        .padding(.bottom, 4)

                    HStack(spacing: 6) {
                        metaChip("\(findings.count) bulgu", bg: .rdFog, fg: .rdCharcoal)
                        confidenceChip
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if !app.isPro {
                        proResultHint
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var proResultHint: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                Text("Pro ile 10 bulguya kadar ve en az %90 AI güveni")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(Color.rdGreenDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.rdGreenSoft.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pro ile 10 bulguya kadar ve en az yüzde 90 AI güveni")
    }

    private var confidenceChip: some View {
        let value = Int(averageConfidence * 100)
        let text = app.isPro ? "Pro AI güveni %\(value)" : "AI güveni %\(value)"
        let icon = app.isPro ? "sparkles" : "arrow.up.circle.fill"

        return Button {
            if !app.isPro {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                Text(text)
                    .rdMono(size: 11, weight: .semibold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(app.isPro ? Color.rdGreenDark : Color.rdHighText)
            .background(app.isPro ? Color.rdGreenSoft : Color.rdHighBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityHint(app.isPro ? "Pro analiz güven göstergesi" : "Pro ile daha kapsamlı analiz bilgisi")
    }

    private func metaChip(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .rdMono(size: 11, weight: .semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var averageConfidence: Double {
        guard !findings.isEmpty else { return 0 }
        return findings.map(\.confidence).reduce(0, +) / Double(findings.count)
    }

    private var formattedDate: String {
        let raw = bundle?.analysis.createdAt ?? ""
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFmt.date(from: raw) ?? Date()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMM · HH:mm"
        return fmt.string(from: date)
    }

    // MARK: - Method selector

    private var methodSelector: some View {
        HStack(spacing: 6) {
            ForEach(RiskMethod.allCases) { m in
                let active = method == m
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.18)) { method = m }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 2) {
                            Text(m.label)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                            Text("R = \(m.formula)")
                                .rdMono(size: 10, weight: .medium)
                                .foregroundStyle(Color.rdSlate)
                        }
                        .frame(maxWidth: .infinity)

                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdGreen)
                                .background(Circle().fill(Color.rdWhite))
                                .offset(x: 4, y: -2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(active ? Color.rdWhite : Color.clear)
                            .shadow(color: active ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.rdFog)
        )
    }

    // MARK: - Methodology summary

    private var methodologySummary: some View {
        let topScore = findings.map { $0.score(for: method) }.max() ?? 0
        let topBand = findings.map { $0.band(for: method) }
            .max(by: { rankFor($0.level) < rankFor($1.level) }) ?? RiskBands.fineKinney(0)
        let totalScore = findings.map { $0.score(for: method) }.reduce(0, +)
        let counts = countsByLevel(method: method)

        return RDCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(method.fullName.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Color.rdSlate)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(scoreText(topScore, method: method))
                                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                                .foregroundStyle(topBand.color)
                                .tracking(-0.5)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text("en yüksek risk")
                                .rdMono(size: 11, weight: .semibold)
                                .foregroundStyle(Color.rdSlate)
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text(topBand.label)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(topBand.color)
                        .background(topBand.color.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 8)

                    VStack(spacing: 5) {
                        Text("Dağılım")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.45)
                            .foregroundStyle(Color.rdSlate)
                            .textCase(.uppercase)
                        HStack(alignment: .bottom, spacing: 6) {
                            countBar(level: .critical, count: counts[.critical] ?? 0)
                            countBar(level: .high,     count: counts[.high] ?? 0)
                            countBar(level: .medium,   count: counts[.medium] ?? 0)
                            countBar(level: .low,      count: counts[.low] ?? 0)
                        }
                    }
                }

                Text(aiSummary(totalScore: totalScore))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.rdGraphite)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func countBar(level: RiskLevel, count: Int) -> some View {
        let height: CGFloat = 50
        let fill = min(CGFloat(count), 5) / 5
        return VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.rdFog)
                RoundedRectangle(cornerRadius: 4)
                    .fill(level.color)
                    .frame(height: max(2, height * fill))
            }
            .frame(width: 22, height: height)
            Text("\(count)")
                .rdMono(size: 10, weight: .bold)
                .foregroundStyle(Color.rdBlack)
            Text(level.shortLabel)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
        }
    }

    private func aiSummary(totalScore: Double) -> AttributedString {
        var attr = AttributedString("AI özeti. ")
        attr.font = .system(size: 12, weight: .bold)

        var rest = AttributedString("\(findings.count) bulgu tespit edildi · Toplam \(method.label) skoru ")
        rest.font = .system(size: 12)
        attr += rest

        var score = AttributedString(scoreText(totalScore, method: method))
        score.font = .system(size: 12, weight: .bold, design: .monospaced)
        attr += score

        var tail = AttributedString(". Aşağıdaki bulgu kartlarında tehlike, hesaplama ve önerilen önlem birlikte gösterilir.")
        tail.font = .system(size: 12)
        attr += tail

        return attr
    }

    // MARK: - Findings list

    private var emptyFindingsCard: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdGreenDark)
                    Text("Tehlike tespit edilmedi")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                }

                Text("Bu analiz için raporlanabilir bir uygunsuzluk bulunmadı. Görsel veya metin yeterince açık değilse farklı bir açıdan tekrar tarama yapılabilir.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tespit edilen tehlikeler · risk hesaplaması".uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)
                .padding(.leading, 4)

            ForEach(Array(sortedFindings.enumerated()), id: \.element.id) { index, finding in
                FindingCard(finding: finding, index: index + 1, method: method, isPro: app.isPro) {
                    selectedFinding = finding
                }

                if let preview = lockedFindingPreview(afterVisibleIndex: index) {
                    LockedFindingPreviewCard(preview: preview) {
                        showPaywall = true
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if !bottomLockedFindingPreviews.isEmpty {
                VStack(spacing: 9) {
                    ForEach(bottomLockedFindingPreviews) { preview in
                        LockedFindingPreviewCard(preview: preview, compact: true) {
                            showPaywall = true
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func lockedFindingPreview(afterVisibleIndex index: Int) -> LockedFindingPreview? {
        guard !app.isPro else { return nil }
        let insertionIndexes = lockedPreviewInsertionIndexes
        guard let previewIndex = insertionIndexes.firstIndex(of: index),
              lockedFindingPreviews.indices.contains(previewIndex)
        else {
            return nil
        }
        return lockedFindingPreviews[previewIndex]
    }

    private var lockedPreviewInsertionIndexes: [Int] {
        let count = sortedFindings.count
        guard count > 0 else { return [] }
        if count == 1 { return [0] }
        if count == 2 { return [0, 1] }
        return [0, min(2, count - 1)]
    }

    private var inlineLockedPreviewCount: Int {
        min(lockedPreviewInsertionIndexes.count, lockedFindingPreviews.count)
    }

    private var bottomLockedFindingPreviews: [LockedFindingPreview] {
        guard !app.isPro else { return [] }
        return Array(lockedFindingPreviews.dropFirst(inlineLockedPreviewCount))
    }

    private var lockedFindingPreviews: [LockedFindingPreview] {
        let start = sortedFindings.count + 1
        let total = max(0, 10 - sortedFindings.count)
        let templates: [(String, RiskLevel, String)] = [
            ("Ek kritik bulgu", .critical, "Detaylı açıklama Pro ile açılır."),
            ("Tolerans dışı durum", .high, "Fine-Kinney ve 5×5 hesabı kilitli."),
            ("Önemli risk alanı", .high, "Kanıt ve aksiyon planı Pro'da görünür."),
            ("Gizli uygunsuzluk", .medium, "Önerilen önlem Pro raporunda açılır."),
            ("Olası risk", .low, "Ek bulgu detayları Pro ile görünür."),
            ("Önemli risk", .high, "PDF/Excel risk tablosuna eklenir."),
            ("Ek saha riski", .medium, "Standart referansları Pro'da açılır."),
            ("Kritik kontrol noktası", .critical, "Detaylı risk hesabı Pro ile açılır."),
            ("Düzeltici aksiyon", .medium, "Aksiyon takibi Pro raporunda görünür."),
            ("Mevzuat referansı", .low, "Kaynak ve standart bilgisi Pro'da açılır.")
        ]
        return (0..<total).map { offset in
            let template = templates[offset % templates.count]
            return LockedFindingPreview(
                number: start + offset,
                title: template.0,
                level: template.1,
                hint: template.2
            )
        }
    }

    // MARK: - Pro upsell

    private var proUpsellCard: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Pro risk analizi")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                        RDProBadge(small: true)
                            .scaleEffect(0.78)
                    }
                    Text("Fine-Kinney, 5×5, PDF/Excel ve özelleştirme açılır.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate.opacity(0.8))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.rdGreen.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        RDButton(
            title: pdfGeneration.isActive ? "Rapor hazırlanıyor..." : isExcelGenerating ? "Excel hazırlanıyor..." : "Rapor Oluştur",
            style: .primary,
            icon: pdfGeneration.isActive || isExcelGenerating ? "hourglass" : "slider.horizontal.3",
            height: 56,
            backgroundOverride: .rdCTA,
            foregroundOverride: .white,
            shadowOverride: Color.rdGreen.opacity(0.16),
            action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                reportOptions = defaultReportOptions(kind: .standard)
                Task { _ = try? await loadProfileLogoIfNeeded() }
                showReportSettings = true
            }
        )
        .disabled(pdfGeneration.isActive || isExcelGenerating)
    }

    // MARK: - Helpers

    private func scoreText(_ value: Double, method: RiskMethod) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))"
    }

    private func countsByLevel(method: RiskMethod) -> [RiskLevel: Int] {
        var dict: [RiskLevel: Int] = [:]
        for f in findings {
            let level = f.band(for: method).level
            dict[level, default: 0] += 1
        }
        return dict
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

    private func generateAndSharePDF(options: PDFReportOptions? = nil, presentShareSheet: Bool = false) {
        guard !pdfGeneration.isActive else { return }
        guard let bundle else {
            pdfError = AppErrorMessage.make(
                AnalysisService.AnalysisError.invalidInput("PDF oluşturmak için tamamlanmış bir analiz bulunamadı."),
                context: "PDF oluşturulamadı",
                fallbackTitle: "PDF oluşturulamadı"
            ).fullText
            return
        }

        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        pdfGeneration.start()
        Task {
            do {
                let reportImage = try await loadReportImage()
                pdfGeneration.advance(to: 0.23)
                let resolvedOptions = options ?? defaultReportOptions(kind: .standard)
                let resolvedLogo = try await loadProfileLogoIfNeeded()
                let input = PDFReportService.ReportInput(
                    bundle: bundle,
                    findings: sortedFindings(for: resolvedOptions.method),
                    profile: app.profile,
                    image: reportImage,
                    companyLogo: reportCompanyLogo ?? resolvedLogo,
                    options: resolvedOptions
                )
                let url = try await PDFReportService.shared.generateAsync(input: input)
                pdfGeneration.advance(to: 0.71)
                if let userID = app.auth.session?.user.id {
                    do {
                        _ = try await AnalysisService.shared.storeReport(
                            userID: userID,
                            bundle: bundle,
                            fileURL: url,
                            kind: resolvedOptions.kind,
                            method: resolvedOptions.method,
                            requestID: requestID,
                            supportID: supportID
                        )
                        pdfGeneration.advance(to: 0.92)
                    } catch {
                        Self.logger.error("Report archive failed after PDF generation support=\(supportID, privacy: .public) request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                        pdfGeneration.advance(to: 0.92)
                    }
                }
                await pdfGeneration.complete()
                if presentShareSheet {
                    activityShareItem = ShareItem(url: url)
                } else {
                    shareItem = ShareItem(url: url)
                }
            } catch {
                pdfGeneration.stop()
                pdfError = AppErrorMessage.make(
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: "PDF oluşturulamadı",
                    fallbackTitle: "PDF oluşturulamadı"
                ).fullText
            }
        }
    }

    private func generateAndShareExcel(method: RiskMethod) {
        guard !isExcelGenerating else { return }
        guard let bundle else {
            pdfError = AppErrorMessage.make(
                AnalysisService.AnalysisError.invalidInput("Excel oluşturmak için tamamlanmış bir analiz bulunamadı."),
                context: "Excel oluşturulamadı",
                fallbackTitle: "Excel oluşturulamadı"
            ).fullText
            return
        }

        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()
        isExcelGenerating = true
        Task {
            do {
                let report = try await AnalysisService.shared.generateExcelReport(
                    analysisID: bundle.analysis.id,
                    method: method,
                    requestID: requestID,
                    supportID: supportID
                )
                let url = try await AnalysisService.shared.reportFileURL(
                    for: report,
                    requestID: requestID,
                    supportID: supportID
                )
                shareItem = ShareItem(url: url)
            } catch {
                pdfError = AppErrorMessage.make(
                    error,
                    context: "Excel oluşturulamadı",
                    fallbackTitle: "Excel oluşturulamadı"
                ).fullText
            }
            isExcelGenerating = false
        }
    }

    private func loadReportImage() async throws -> UIImage? {
        let resolvedPath: String?
        if let photoPath {
            resolvedPath = photoPath
        } else if let analysisID = bundle?.analysis.id {
            let paths = try await AnalysisService.shared.firstPhotoPaths(analysisIDs: [analysisID])
            resolvedPath = paths[analysisID]
        } else {
            resolvedPath = nil
        }

        guard let resolvedPath else {
            return localPreviewImage
        }

        let data = try await AnalysisService.shared.photoData(path: resolvedPath)
        guard let image = UIImage(data: data) else {
            throw AnalysisService.AnalysisError.storageFailed("Analiz fotoğrafı indirildi ancak görüntü formatı açılamadı.")
        }
        return image
    }

    private func sortedFindings(for reportMethod: RiskMethod) -> [Finding] {
        findings.sorted {
            let leftBand = $0.band(for: reportMethod).level
            let rightBand = $1.band(for: reportMethod).level
            let leftRank = rankFor(leftBand)
            let rightRank = rankFor(rightBand)
            if leftRank != rightRank { return leftRank > rightRank }

            let leftScore = $0.score(for: reportMethod)
            let rightScore = $1.score(for: reportMethod)
            if leftScore != rightScore { return leftScore > rightScore }

            return $0.confidence > $1.confidence
        }
    }

    private func defaultReportOptions(kind: PDFReportKind = .standard) -> PDFReportOptions {
        PDFReportOptions(
            kind: kind,
            method: method,
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
}

// MARK: - Report Settings

private enum ReportOutputFormat: String, CaseIterable, Identifiable {
    case pdf
    case excel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF rapor"
        case .excel: return "Excel tablo"
        }
    }

    var subtitle: String {
        switch self {
        case .pdf: return "PDF olarak rapor oluşturulur."
        case .excel: return "Excel tablo olarak oluşturulur."
        }
    }

    var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .excel: return "tablecells"
        }
    }
}

struct ReportSettingsSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var options: PDFReportOptions
    @Binding var companyLogo: UIImage?
    let profile: UserProfile?
    let isPro: Bool
    let onGenerate: () -> Void
    let onGenerateExcel: (() -> Void)?
    let onPaywall: () -> Void
    let onClose: () -> Void
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var outputFormat: ReportOutputFormat = .pdf

    private var isDarkMode: Bool { colorScheme == .dark }
    private var lockedCardBackground: Color {
        isDarkMode ? Color.rdWhite.opacity(0.08) : Color(hex: "#FFFCF2")
    }
    private var lockedCardStroke: Color {
        isDarkMode ? Color.rdGreen.opacity(0.26) : Color(hex: "#F6C343").opacity(0.5)
    }
    private var lockedIconBackground: Color {
        isDarkMode ? Color.rdGreenSoft.opacity(0.20) : Color(hex: "#FFF2BD")
    }
    private var lockedIconForeground: Color {
        isDarkMode ? Color.rdGreen : Color(hex: "#9A6B00")
    }
    private var lockedPreviewBackground: Color {
        isDarkMode ? Color.rdWhite.opacity(0.07) : Color.rdWhite.opacity(0.58)
    }
    private var lockedPreviewPillBackground: Color {
        isDarkMode ? Color.rdWhite.opacity(0.09) : Color.rdFog.opacity(0.78)
    }
    private var lockedPreviewFieldBackground: Color {
        isDarkMode ? Color.rdWhite.opacity(0.08) : Color.rdWhite.opacity(0.76)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    reportTypeSection

                    if options.kind == .riskAnalysis {
                        VStack(alignment: .leading, spacing: 18) {
                            methodSection
                            outputFormatSection
                            identitySection
                            companyLogoSection
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                    }

                    RDButton(title: primaryButtonTitle,
                             style: .detect,
                             icon: primaryButtonIcon,
                             height: 54,
                             backgroundOverride: .rdCTA,
                             foregroundOverride: .white,
                             shadowOverride: Color.rdGreen.opacity(0.16),
                             action: {
                                 if options.kind == .riskAnalysis, outputFormat == .excel, let onGenerateExcel {
                                     onGenerateExcel()
                                 } else {
                                     onGenerate()
                                 }
                             })
                        .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(Color.rdPaper)
            .navigationTitle("Rapor Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: options.kind)
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: outputFormat)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat", action: onClose)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        if options.kind == .standard { return "Rapor oluştur" }
        return outputFormat == .excel ? "Excel risk tablosu oluştur" : "Risk analizi PDF oluştur"
    }

    private var primaryButtonIcon: String {
        if options.kind == .standard { return "doc.richtext.fill" }
        return outputFormat == .excel ? "tablecells" : "doc.text.magnifyingglass"
    }

    private var reportTypeSection: some View {
        VStack(spacing: 14) {
            reportKindRow(
                kind: .standard,
                title: "Standart Rapor",
                subtitle: "Hızlı Uygunsuzluk Raporu, ek bilgi girmeden oluşturulur.",
                icon: "doc.richtext"
            )
            reportKindRow(
                kind: .riskAnalysis,
                title: "Risk Analizi Tablosu",
                subtitle: "Fine-Kinney veya 5×5 Matris Metodu PDF ve Excel çıktısı, ayrıca özelleştirilebilir alanlar.",
                icon: "tablecells",
                locked: !isPro
            )
        }
    }

    private func reportKindRow(
        kind: PDFReportKind,
        title: String,
        subtitle: String,
        icon: String,
        locked: Bool = false
    ) -> some View {
        let active = options.kind == kind
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if locked {
                onPaywall()
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    options.kind = kind
                    if kind == .standard {
                        outputFormat = .pdf
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: locked ? 10 : 0) {
                HStack(spacing: 14) {
                    Image(systemName: locked ? "lock.fill" : icon)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? Color.white : locked ? lockedIconForeground : Color.rdGreenDark)
                        .frame(width: 58, height: 58)
                        .background(active ? Color.rdGreen : locked ? lockedIconBackground : Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            if locked {
                                RDProBadge(small: true)
                                    .scaleEffect(0.82)
                            }
                        }
                        Text(subtitle)
                            .font(.system(size: 13.5, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: active ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? Color.rdGreen : Color.rdSlate.opacity(0.32))
                }

                if locked {
                    proLockedPreview
                }
            }
            .padding(18)
            .background(active ? Color.rdGreenSoft.opacity(0.65) : locked ? lockedCardBackground : Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(active ? Color.rdGreen.opacity(0.55) : locked ? lockedCardStroke : Color.rdLine, lineWidth: active ? 1.4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: active ? Color.rdGreen.opacity(0.12) : Color.clear, radius: 14, x: 0, y: 8)
        }
        .frame(minHeight: locked ? 286 : 136)
        .buttonStyle(RDPressableButtonStyle())
    }

    private var proLockedPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                lockedPreviewPill("Fine-Kinney", detail: "R = O × F × Ş", icon: "function")
                lockedPreviewPill("5×5 Matris", detail: "R = O × Ş", icon: "square.grid.2x2")
            }
            HStack(spacing: 10) {
                lockedPreviewPill("PDF", detail: "Denetim raporu", icon: "doc.richtext")
                lockedPreviewPill("Excel", detail: "Risk tablosu", icon: "tablecells")
            }
            HStack(spacing: 10) {
                lockedPreviewField("Hazırlayan")
                lockedPreviewField("Firma / logo")
            }
        }
        .padding(12)
        .background(lockedPreviewBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(lockedCardStroke.opacity(isDarkMode ? 0.7 : 0.52), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isDarkMode ? 0.92 : 0.72)
        .allowsHitTesting(false)
    }

    private func lockedPreviewPill(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .stroke(Color.rdSlate.opacity(0.38), lineWidth: 1.5)
                .frame(width: 17, height: 17)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 26, height: 26)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack.opacity(0.76))
                    .lineLimit(1)
                Text(detail)
                    .rdMono(size: 9.5)
                    .foregroundStyle(Color.rdSlate.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(lockedPreviewPillBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func lockedPreviewField(_ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "text.cursor")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.rdSlate.opacity(0.78))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(lockedPreviewFieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.rdLine.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private var outputFormatSection: some View {
        if onGenerateExcel != nil {
            settingsSection(title: "DOSYA TÜRÜ") {
                HStack(spacing: 8) {
                    ForEach(ReportOutputFormat.allCases) { format in
                        let active = outputFormat == format
                        Button {
                            outputFormat = format
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 6) {
                                    Image(systemName: format.icon)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                    VStack(spacing: 2) {
                                        Text(format.title)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                        Text(format.subtitle)
                                            .font(.system(size: 10, design: .rounded))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                if active {
                                    selectedCheckmark
                                }
                            }
                            .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 82)
                            .background(active ? Color.rdWhite : Color.rdFog)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(active ? Color.rdSelected : Color.rdLine, lineWidth: active ? 1.5 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var methodSection: some View {
        settingsSection(title: "RİSK ANALİZ METODU") {
            HStack(spacing: 8) {
                ForEach(RiskMethod.allCases) { method in
                    let active = options.method == method
                    Button {
                        options.method = method
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 4) {
                            Text(method.label)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("R = \(method.formula)")
                                .rdMono(size: 10)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(alignment: .topTrailing) {
                            if active {
                                selectedCheckmark
                                    .offset(x: -8, y: 8)
                            }
                        }
                        .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                        .background(active ? Color.rdWhite : Color.rdFog)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(active ? Color.rdSelected : Color.rdLine, lineWidth: active ? 1.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedCheckmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Color.rdGreen)
            .background(Circle().fill(Color.rdWhite))
    }

    private var identitySection: some View {
        settingsSection(title: "OPSİYONEL BİLGİLER") {
            VStack(spacing: 10) {
                labeledField("Hazırlayan", text: $options.preparedBy, placeholder: profile?.displayName ?? "Ad Soyad")
                labeledField("Firma", text: $options.companyName, placeholder: profile?.companyName ?? "Firma adı")
            }
        }
    }

    private var companyLogoSection: some View {
        settingsSection(title: "OPSİYONEL LOGO") {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.rdWhite)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.rdLine, lineWidth: 1)
                        )
                    if let companyLogo {
                        Image(uiImage: companyLogo)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } else {
                        Image(systemName: "building.2.crop.circle")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(width: 68, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(companyLogo == nil ? "Logo seçilmedi" : "Logo rapora eklenecek")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Profilindeki logo varsayılan gelir; istersen bu çıktı için farklı logo seçebilirsin.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.rdGreenDark)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onChange(of: selectedLogoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        companyLogo = image
                    }
                }
            }
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.rdSlate)
                .padding(.leading, 4)
            content()
        }
    }

    private func optionRow(title: String, subtitle: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? Color.rdGreenDark : Color.rdSlate)
                    .frame(width: 38, height: 38)
                    .background(active ? Color.rdGreenSoft : Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? Color.rdGreen : Color.rdSlate.opacity(0.35))
            }
            .padding(12)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(active ? Color.rdGreen.opacity(0.45) : Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            TextField(placeholder, text: text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.rdWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Locked Finding Preview

private struct LockedFindingPreview: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let level: RiskLevel
    let hint: String
}

private struct LockedFindingPreviewCard: View {
    let preview: LockedFindingPreview
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(preview.number)")
                    .rdMono(size: compact ? 11 : 12, weight: .bold)
                    .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                    .foregroundStyle(Color.rdBlack.opacity(0.78))
                    .background(Color.rdWhite.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.rdLine.opacity(0.7), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                    HStack(spacing: 7) {
                        Text(preview.title)
                            .font(.system(size: compact ? 13 : 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack.opacity(0.86))
                            .lineLimit(1)
                        RDChip(level: preview.level, label: preview.level.label)
                            .opacity(0.96)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                        Text(preview.hint)
                            .font(.system(size: compact ? 11 : 11.5, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.rdSlate.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RDProBadge(small: true)
                    .scaleEffect(0.78)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 9 : 11)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.rdGreenSoft.opacity(compact ? 0.28 : 0.34))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.rdGreen.opacity(compact ? 0.22 : 0.32), lineWidth: 1)
                    )
            )
            .overlay {
                LinearGradient(
                    colors: [Color.clear, Color.rdWhite.opacity(0.30)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false)
            }
            .opacity(compact ? 0.92 : 0.96)
        }
        .buttonStyle(RDPressableButtonStyle())
    }
}

// MARK: - FindingCard

struct FindingCard: View {
    let finding: Finding
    let index: Int
    let method: RiskMethod
    let isPro: Bool
    let action: () -> Void

    var body: some View {
        let band = finding.band(for: method)
        let score = finding.score(for: method)
        let max: Double = method == .fineKinney ? 1000 : 25

        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index)")
                    .rdMono(size: 12, weight: .bold)
                    .frame(width: 26, height: 26)
                    .background(Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color.rdBlack)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(finding.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RDChip(level: band.level, label: band.label)
                    }
                    Text(finding.description)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    scoreBlock(band: band, score: score, max: max)

                    actionBlock

                    findingMetaCards(band: band)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .fill(Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: RDRadius.lg)
                            .stroke(Color.rdLine, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private func scoreBlock(band: RiskBand, score: Double, max: Double) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("\(Int(score))")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
                Text(method == .fineKinney ? "F-KINNEY" : "5×5")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .opacity(0.85)
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(.white)
            .background(band.color)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(band.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(band.color)
                Text("R = \(finding.formula(for: method))")
                    .rdMono(size: 11)
                    .foregroundStyle(Color.rdSlate)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.rdFog)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(band.color)
                            .frame(width: geo.size.width * CGFloat(min(1, score / max)))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.rdWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
        )
    }

    private var actionBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .padding(.top, 2)
            (
                Text("Önlem · ").font(.system(size: 12, weight: .bold, design: .rounded)) +
                Text(finding.action).font(.system(size: 12, design: .rounded))
            )
            .foregroundStyle(Color.rdGraphite)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdGreenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func findingMetaCards(band: RiskBand) -> some View {
        HStack(alignment: .top, spacing: 8) {
            infoCard(
                icon: "checkmark.seal.fill",
                title: "Plan",
                value: band.action,
                tint: band.color
            )
            infoCard(
                icon: isPro ? "books.vertical.fill" : "lock.fill",
                title: "Mevzuat",
                value: isPro ? (finding.references.isEmpty ? "Kontrol edilmeli" : finding.references) : "Pro'da açık",
                tint: isPro ? Color.rdGreenDark : Color.rdSlate
            )
        }
    }

    private func infoCard(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(Color.rdSlate)
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGraphite)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.rdFog.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct ResultPhotoThumbnail: View {
    let image: UIImage?
    let path: String?
    let isTextAnalysis: Bool
    var cornerRadius: CGFloat
    @State private var remoteImage: UIImage?
    @State private var loadedPath: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let remoteImage {
                    Image(uiImage: remoteImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    AnalysisThumbnail(path: nil, isTextAnalysis: isTextAnalysis, cornerRadius: cornerRadius)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .task(id: path) {
            await loadRemoteIfNeeded()
        }
    }

    private func loadRemoteIfNeeded() async {
        guard let path, loadedPath != path else { return }
        loadedPath = path
        do {
            let data = try await AnalysisService.shared.photoData(path: path)
            if let downloaded = UIImage(data: data) {
                remoteImage = downloaded
            }
        } catch {
            remoteImage = nil
        }
    }
}

// MARK: - Risk Matrix

struct RiskMatrix: View {
    let findings: [Finding]
    let method: RiskMethod

    var body: some View {
        let dots = computeDots(findings: findings, method: method)
        let grid: [[RiskLevel]] = [
            [.high, .high, .critical, .critical],
            [.medium, .medium, .high, .critical],
            [.low, .medium, .medium, .high],
            [.low, .low, .medium, .high]
        ]

        return HStack(alignment: .top, spacing: 8) {
            Text("ETKİ →")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(Color.rdSlate)
                .rotationEffect(.degrees(-90))
                .frame(width: 14)

            VStack(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                          spacing: 4) {
                    ForEach(0..<16, id: \.self) { i in
                        let row = i / 4
                        let col = i % 4
                        let level = grid[row][col]
                        let dot = dots.first { $0.x == col && $0.y == 3 - row }

                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(level.bgColor)
                            if let d = dot {
                                Text("\(d.n)")
                                    .rdMono(size: 11, weight: .bold)
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(d.level.color)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                }

                Text("OLASILIK →")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(Color.rdSlate)
            }
        }
    }

    private struct MatrixDot {
        let x: Int
        let y: Int
        let level: RiskLevel
        let n: Int
    }

    private func computeDots(findings: [Finding], method: RiskMethod) -> [MatrixDot] {
        findings.enumerated().map { index, f in
            let band = f.band(for: method)
            let xy = matrixPosition(finding: f, method: method)
            return MatrixDot(x: xy.x, y: xy.y, level: band.level, n: index + 1)
        }
    }

    private func matrixPosition(finding: Finding, method: RiskMethod) -> (x: Int, y: Int) {
        switch method {
        case .matrix5x5:
            // 1..5 → 0..3 ([0,1] → 0; 2 → 1; 3 → 2; 4..5 → 3)
            let x = bucket1to5(finding.m5.probability)
            let y = bucket1to5(finding.m5.severity)
            return (x, y)
        case .fineKinney:
            // O 0.2..10 ve Ş 1..100 → 0..3
            let x = bucketLog(finding.fk.probability * finding.fk.frequency / 5, max: 60)
            let y = bucketLog(finding.fk.severity, max: 100)
            return (x, y)
        }
    }

    private func bucket1to5(_ value: Int) -> Int {
        switch value {
        case ...1: return 0
        case 2:    return 1
        case 3:    return 2
        default:   return 3
        }
    }

    private func bucketLog(_ value: Double, max: Double) -> Int {
        let normalized = max > 0 ? value / max : 0
        switch normalized {
        case ..<0.10: return 0
        case ..<0.30: return 1
        case ..<0.60: return 2
        default:      return 3
        }
    }
}

#Preview {
    ResultView(onClose: {}, onPdf: {})
        .environmentObject({ let s = AppState(); s.flow = .main; return s }())
}
