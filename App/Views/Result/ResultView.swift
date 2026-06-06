import SwiftUI
import UIKit
import PhotosUI
import OSLog

struct ResultView: View {
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "ResultView")

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var selectedReportCompany: Company?
    @State private var reportCompanyLogo: UIImage?
    @State private var reportQuotaExhausted: Bool = false
    @State private var freeRiskAnalysisTrialUsed: Bool = false
    @State private var reportSettingsDetent: PresentationDetent = .height(430)
    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }
    private var freeRiskAnalysisTrialRemaining: Int {
        app.currentTier == .free && !freeRiskAnalysisTrialUsed ? 1 : 0
    }

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
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, findings.isEmpty ? 110 : 16)
            }
            .clipped()
            .zIndex(0)

            if !findings.isEmpty {
                stickyReportCTA
                    .zIndex(1)
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
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(item: $shareItem) { item in
            DocumentPreview(url: item.url)
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(item: $activityShareItem) { item in
            ShareSheet(items: [item.url])
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showReportSettings) {
            ReportSettingsSheet(
                options: $reportOptions,
                selectedCompany: $selectedReportCompany,
                companyLogo: $reportCompanyLogo,
                presentationDetent: $reportSettingsDetent,
                profile: app.profile,
                accessTier: app.currentTier,
                canUseRiskAnalysis: app.planCapabilities.canUseDetailedRiskTable,
                freeRiskAnalysisTrialRemaining: freeRiskAnalysisTrialRemaining,
                reportQuotaExhausted: reportQuotaExhausted,
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
            .presentationDetents([.height(430), .large], selection: $reportSettingsDetent)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
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
            FreeAwarePaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task { await app.auth.refreshProfile() }
                        })
            .preferredColorScheme(preferredModalColorScheme)
        }
        .task(id: app.profile?.preferredMethod?.rawValue) {
            if let preferredMethod = app.profile?.preferredMethod?.domain {
                method = preferredMethod
            }
        }
        .task(id: bundle?.analysis.companyID) {
            await loadInitialReportCompanyIfNeeded()
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
                .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))

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
                .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
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
                        .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(formattedDate) · \(canvasLabel)")
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
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
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: RDFontScale.size(8.5), weight: .bold, design: .rounded))
                    .padding(.top, 2)
                Text("Pro ile 10 Bulgu ve En az %90 Güven")
                    .font(.system(size: RDFontScale.size(10.5), weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.rdGreenDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.rdGreenSoft.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .accessibilityLabel("Pro ile 10 bulgu ve en az yüzde 90 güven")
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
                    .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
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
                                .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                                .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                            Text("R = \(m.formula)")
                                .rdMono(size: 10, weight: .medium)
                                .foregroundStyle(Color.rdSlate)
                        }
                        .frame(maxWidth: .infinity)

                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
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
        let counts = countsByLevel(method: method)

        return RDCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(method.fullName.uppercased())
                            .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Color.rdSlate)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(scoreText(topScore, method: method))
                                .font(.system(size: RDFontScale.size(30), weight: .heavy, design: .monospaced))
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
                                .font(.system(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
                            Text(topBand.label)
                                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
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
                            .font(.system(size: RDFontScale.size(9), weight: .bold, design: .rounded))
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
                .font(.system(size: RDFontScale.size(8), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
        }
    }

    // MARK: - Findings list

    private var emptyFindingsCard: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: RDFontScale.size(18), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdGreenDark)
                    Text("Tehlike tespit edilmedi")
                        .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                }

                Text("Bu analiz için raporlanabilir bir uygunsuzluk bulunmadı. Görsel veya metin yeterince açık değilse farklı bir açıdan tekrar tarama yapılabilir.")
                    .font(.system(size: RDFontScale.size(13), design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tespit edilen tehlikeler · risk hesaplaması".uppercased())
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)
                .padding(.leading, 4)

            ForEach(Array(sortedFindings.enumerated()), id: \.element.id) { index, finding in
                FindingCard(finding: finding, index: index + 1, method: method, currentTier: app.currentTier) {
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
        guard app.currentTier == .free else { return nil }
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
        guard app.currentTier == .free else { return [] }
        return Array(lockedFindingPreviews.dropFirst(inlineLockedPreviewCount))
    }

    private var lockedFindingPreviews: [LockedFindingPreview] {
        let start = sortedFindings.count + 1
        let total = max(0, 10 - sortedFindings.count)
        let templates: [(String, RiskLevel, String)] = [
            ("Ek kritik bulgu", .critical, "Detaylı açıklama Pro ile açılır."),
            ("Tolerans dışı durum", .high, "Fine-Kinney ve 5×5 hesabı kilitli."),
            ("Önemli risk alanı", .high, "Kanıt ve aksiyon planı Pro'da görünür."),
            ("Gizli uygunsuzluk", .medium, "Önlem / kontrol tedbirleri Plus ile görünür."),
            ("Olası risk", .low, "Ek bulgu detayları Plus ile görünür."),
            ("Önemli risk", .high, "PDF/Excel risk tablosuna eklenir."),
            ("Ek saha riski", .medium, "Standart referansları Plus'ta açılır."),
            ("Kritik kontrol noktası", .critical, "Detaylı risk hesabı Pro ile açılır."),
            ("Düzeltici aksiyon", .medium, "Aksiyon takibi Plus raporunda görünür."),
            ("Mevzuat referansı", .low, "Kaynak ve standart bilgisi Plus'ta açılır.")
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

    // MARK: - Report CTA

    private var stickyReportCTA: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.rdPaper.opacity(0), Color.rdPaper.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)

            reportCTAButton
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .padding(.top, 2)
                .background(Color.rdPaper.opacity(0.96))
        }
    }

    private var reportCTAButton: some View {
        Button(action: openReportSettings) {
            ZStack {
                HStack {
                    Spacer()
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: RDFontScale.size(18), weight: .heavy, design: .rounded))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.rdOnyx)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 8) {
                    Image(systemName: pdfGeneration.isActive || isExcelGenerating ? "hourglass" : "slider.horizontal.3")
                        .font(.system(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                    Text(pdfGeneration.isActive ? "Rapor hazırlanıyor..." : isExcelGenerating ? "Excel hazırlanıyor..." : "Rapor Oluştur")
                        .font(.system(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 56)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.horizontal, 10)
            .background(Color.rdCTA)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.rdGreen.opacity(0.16), radius: 18, x: 0, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(pdfGeneration.isActive || isExcelGenerating)
    }

    private func openReportSettings() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await app.refreshPlanState()
            _ = await refreshReportQuotaState()
            await refreshFreeRiskAnalysisTrialState()
            await loadInitialReportCompanyIfNeeded()
            reportOptions = resolvedReportOptions(defaultReportOptions(kind: .standard), company: selectedReportCompany)
            reportSettingsDetent = .height(430)
            showReportSettings = true
            if !reportQuotaExhausted {
                _ = try? await loadProfileLogoIfNeeded()
            }
        }
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
                    reportOptions = defaultReportOptions(kind: .standard)
                    reportSettingsDetent = .height(430)
                    showReportSettings = true
                    return
                }
                let reportImage = try await loadReportImage()
                pdfGeneration.advance(to: 0.23)
                let companyLogo = try await loadCompanyLogo(for: company)
                let profileLogo = try await loadProfileLogoIfNeeded()
                let resolvedLogo = companyLogo ?? profileLogo
                #if DEBUG
                let uiTestLogo = Self.uiTestReportLogoIfRequested()
                #else
                let uiTestLogo: UIImage? = nil
                #endif
                let input = PDFReportService.ReportInput(
                    bundle: bundle,
                    findings: sortedFindings(for: resolvedOptions.method),
                    profile: app.profile,
                    image: reportImage,
                    companyLogo: reportCompanyLogo ?? resolvedLogo ?? uiTestLogo,
                    options: resolvedOptions
                )
                let url = try await PDFReportService.shared.generateAsync(input: input)
                pdfGeneration.advance(to: 0.71)
                var archiveWarning: String?
                if let userID = app.auth.session?.user.id {
                    do {
                        _ = try await AnalysisService.shared.storeReport(
                            userID: userID,
                            bundle: bundle,
                            fileURL: url,
                            kind: resolvedOptions.kind,
                            method: resolvedOptions.method,
                            company: company,
                            requestID: requestID,
                            supportID: supportID
                        )
                        try await backfillAnalysisCompanyIfNeeded(bundle: bundle, company: company)
                        markFreeRiskAnalysisTrialUsedIfNeeded(for: resolvedOptions.kind)
                        pdfGeneration.advance(to: 0.92)
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
                        pdfGeneration.advance(to: 0.92)
                    }
                }
                markFreeRiskAnalysisTrialUsedIfNeeded(for: resolvedOptions.kind)
                await pdfGeneration.complete()
                if let archiveWarning {
                    pdfError = archiveWarning
                }
                if presentShareSheet {
                    activityShareItem = ShareItem(url: url)
                } else {
                    shareItem = ShareItem(url: url)
                }
            } catch {
                pdfGeneration.stop()
                if handleReportQuotaIfNeeded(error) {
                    return
                }
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
                let resolvedOptions = resolvedReportOptions(reportOptions, company: selectedReportCompany)
                if await riskAnalysisTrialExhaustedBeforeGeneration() {
                    isExcelGenerating = false
                    return
                }
                if !shouldBypassReportQuota(for: resolvedOptions),
                   await refreshReportQuotaState() {
                    reportOptions.kind = .standard
                    reportSettingsDetent = .height(430)
                    showReportSettings = true
                    isExcelGenerating = false
                    return
                }
                let report = try await AnalysisService.shared.generateExcelReport(
                    analysisID: bundle.analysis.id,
                    method: method,
                    language: reportOptions.language,
                    companyID: selectedReportCompany?.id,
                    requestID: requestID,
                    supportID: supportID
                )
                try await backfillAnalysisCompanyIfNeeded(bundle: bundle, company: selectedReportCompany)
                markFreeRiskAnalysisTrialUsedIfNeeded(for: .riskAnalysis)
                let url = try await AnalysisService.shared.reportFileURL(
                    for: report,
                    requestID: requestID,
                    supportID: supportID
                )
                shareItem = ShareItem(url: url)
            } catch {
                if handleReportQuotaIfNeeded(error) {
                    isExcelGenerating = false
                    return
                }
                pdfError = AppErrorMessage.make(
                    error,
                    context: "Excel oluşturulamadı",
                    fallbackTitle: "Excel oluşturulamadı"
                ).fullText
            }
            isExcelGenerating = false
        }
    }

    @discardableResult
    private func handleReportQuotaIfNeeded(_ error: Error) -> Bool {
        if AppErrorMessage.isFreeRiskAnalysisTrialExhausted(error.localizedDescription) {
            freeRiskAnalysisTrialUsed = true
            reportQuotaExhausted = false
            reportOptions.kind = .standard
            reportSettingsDetent = .height(430)
            showReportSettings = true
            return true
        }
        guard AppErrorMessage.isReportQuotaExceeded(error.localizedDescription) else { return false }
        reportQuotaExhausted = true
        reportOptions.kind = .standard
        reportSettingsDetent = .height(430)
        showReportSettings = true
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

    private func refreshFreeRiskAnalysisTrialState() async {
        guard app.currentTier == .free else {
            freeRiskAnalysisTrialUsed = false
            return
        }
        do {
            let usage = try await AnalysisService.shared.freeRiskAnalysisTrialUsage()
            freeRiskAnalysisTrialUsed = usage.isExhausted
        } catch {
            // Keep the last known local state. A transient auth/network failure should not
            // visually re-grant the one-time risk analysis trial.
        }
    }

    private func shouldBypassReportQuota(for options: PDFReportOptions) -> Bool {
        app.currentTier == .free && options.kind == .riskAnalysis && !freeRiskAnalysisTrialUsed
    }

    @MainActor
    private func markFreeRiskAnalysisTrialUsedIfNeeded(for kind: PDFReportKind) {
        guard app.currentTier == .free, kind == .riskAnalysis else { return }
        freeRiskAnalysisTrialUsed = true
    }

    private func riskAnalysisTrialExhaustedBeforeGeneration() async -> Bool {
        guard app.currentTier == .free else { return false }
        await refreshFreeRiskAnalysisTrialState()
        guard freeRiskAnalysisTrialUsed else { return false }
        reportOptions.kind = .standard
        reportSettingsDetent = .height(430)
        showReportSettings = true
        pdfError = AppErrorMessage.make(
            rawMessage: "free_risk_analysis_trial_exhausted:1/1",
            context: "Risk analizi tablosu oluşturulamadı",
            fallbackTitle: "Risk analizi tablosu oluşturulamadı"
        ).fullText
        return true
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
        var options = PDFReportOptions(
            kind: kind,
            method: method,
            preparedBy: app.profile?.displayName ?? "",
            preparedTitle: app.profile?.title ?? "",
            certificateNumber: app.profile?.certificateNumber ?? "",
            companyName: app.profile?.companyName ?? "",
            companyInfo: app.profile?.phone ?? "",
            companyID: nil,
            language: app.languagePreference
        )
        #if DEBUG
        if Self.usesUITestLongReportFields {
            options.preparedBy = "Test Çok Uzun Uzman Adı Soyadı Denetim ve Risk Yönetimi Sorumlusu"
            options.preparedTitle = "A Sınıfı İş Güvenliği Uzmanı ve Çok Tehlikeli Saha Denetim Koordinatörü"
            options.certificateNumber = "TEST-BELGE-2026-ÇOK-UZUN-0000000001"
            options.companyName = "Test Çok Uzun Firma Adı Sanayi ve Ticaret Anonim Şirketi Kuzey Marmara Bölge Müdürlüğü"
            options.companyInfo = "Çok Tehlikeli · Bakım ve Üretim Sahası · Uzun şirket bilgisi satır kırılım kontrolü"
        }
        #endif
        return options
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

    private func loadInitialReportCompanyIfNeeded() async {
        guard selectedReportCompany == nil,
              let companyID = bundle?.analysis.companyID,
              app.currentTier.isPaid
        else { return }
        do {
            let companies = try await CompanyService.shared.listCompanies(includeArchived: true)
            selectedReportCompany = companies.first { $0.id == companyID }
        } catch {
            selectedReportCompany = nil
        }
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

    private func loadCompanyLogo(for company: Company?) async throws -> UIImage? {
        guard let path = company?.logoPath, !path.isEmpty else { return nil }
        return try await CompanyService.shared.logoImage(path: path)
    }

    #if DEBUG
    private static var usesUITestLongReportFields: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_LONG_REPORT_FIELDS")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_LONG_REPORT_FIELDS"] == "1"
    }

    private static var usesUITestReportLogo: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_REPORT_LOGO")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_REPORT_LOGO"] == "1"
    }

    private static func uiTestReportLogoIfRequested() -> UIImage? {
        guard usesUITestReportLogo else { return nil }
        let size = CGSize(width: 180, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 0.96, green: 0.73, blue: 0.05, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18).fill()
            UIColor(red: 0.02, green: 0.03, blue: 0.03, alpha: 1).setFill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .black),
                .foregroundColor: UIColor(red: 0.02, green: 0.03, blue: 0.03, alpha: 1)
            ]
            NSString(string: "RD").draw(in: CGRect(x: 46, y: 18, width: 90, height: 44), withAttributes: attrs)
            UIColor.white.withAlphaComponent(0.72).setStroke()
            let path = UIBezierPath(roundedRect: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16), cornerRadius: 14)
            path.lineWidth = 4
            path.stroke()
            _ = context
        }
    }
    #endif
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
    @Binding var selectedCompany: Company?
    @Binding var companyLogo: UIImage?
    @Binding var presentationDetent: PresentationDetent
    let profile: UserProfile?
    let accessTier: SubscriptionTier
    let canUseRiskAnalysis: Bool
    let freeRiskAnalysisTrialRemaining: Int
    let reportQuotaExhausted: Bool
    let onGenerate: () -> Void
    let onGenerateExcel: (() -> Void)?
    let onPaywall: () -> Void
    let onClose: () -> Void
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var outputFormat: ReportOutputFormat = .pdf
    @State private var showCompanyPicker = false
    @State private var showReportOverrides = false

    private var isDarkMode: Bool { colorScheme == .dark }
    private var lockedCardBackground: Color {
        if reportQuotaExhausted { return Color.rdCriticalBg.opacity(isDarkMode ? 0.14 : 0.34) }
        return isDarkMode ? Color.rdWhite.opacity(0.08) : Color(hex: "#FFFCF2")
    }
    private var lockedCardStroke: Color {
        if reportQuotaExhausted { return Color.rdCritical.opacity(isDarkMode ? 0.34 : 0.42) }
        return isDarkMode ? SubscriptionTier.plus.accentColor.opacity(0.30) : SubscriptionTier.plus.accentColor.opacity(0.46)
    }
    private var lockedIconBackground: Color {
        if reportQuotaExhausted { return Color.rdCriticalBg.opacity(isDarkMode ? 0.24 : 1) }
        return SubscriptionTier.plus.accentSoftColor
    }
    private var lockedIconForeground: Color {
        if reportQuotaExhausted { return Color.rdCriticalText }
        return SubscriptionTier.plus.accentTextColor
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
    private var riskAnalysisLocked: Bool {
        if hasFreeRiskAnalysisTrial { return false }
        return reportQuotaExhausted || !canUseRiskAnalysis
    }
    private var standardReportLocked: Bool {
        reportQuotaExhausted
    }
    private var hasFreeRiskAnalysisTrial: Bool {
        accessTier == .free && freeRiskAnalysisTrialRemaining > 0
    }
    private var shouldShowRiskAnalysisStatusBadge: Bool {
        accessTier == .free || reportQuotaExhausted || !canUseRiskAnalysis
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if options.kind == .riskAnalysis {
                        VStack(alignment: .leading, spacing: 18) {
                            reportTypeSection
                            companySelectionSection
                            methodSection
                            outputFormatSection
                            identitySection
                            reportOverridesSection
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                    } else {
                        reportTypeSection
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 96)
                .keyboardAdaptivePadding(extra: 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.rdPaper)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                reportSettingsStickyCTA
            }
            .navigationTitle(RDLocalization.shared.text(.reportCreateTitle, language: options.language))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("report.settings")
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: options.kind)
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: outputFormat)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
        }
        .sheet(isPresented: $showCompanyPicker) {
            CompanyPickerSheet(
                title: "Rapor firması",
                accessTier: accessTier,
                selectedCompanyID: selectedCompany?.id,
                allowNoCompany: true,
                onSelect: { company in
                    selectedCompany = company
                    applyCompanyToOptions(company)
                },
                onPaywall: onPaywall
            )
            .presentationDetents(CompanyPickerSheet.presentationDetents(for: accessTier))
            .presentationDragIndicator(.visible)
            .preferredColorScheme(colorScheme)
        }
    }

    private var primaryButtonTitle: String {
        if reportQuotaExhausted && !(options.kind == .riskAnalysis && hasFreeRiskAnalysisTrial) {
            switch accessTier {
            case .free: return "Yükselt"
            case .plus: return "Pro'ya yükselt"
            case .pro: return "Tamam"
            }
        }
        if options.kind == .standard { return "Rapor oluştur" }
        return outputFormat == .excel ? "Excel risk tablosu oluştur" : "Risk analizi PDF oluştur"
    }

    private var primaryButtonIcon: String {
        if reportQuotaExhausted && !(options.kind == .riskAnalysis && hasFreeRiskAnalysisTrial) {
            return "arrow.up.circle.fill"
        }
        if options.kind == .standard { return "doc.richtext.fill" }
        return outputFormat == .excel ? "tablecells" : "doc.text.magnifyingglass"
    }

    private var reportSettingsStickyCTA: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.rdPaper.opacity(0), Color.rdPaper.opacity(0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 14)
            .allowsHitTesting(false)

            RDButton(title: primaryButtonTitle,
                     style: .detect,
                     icon: primaryButtonIcon,
                     height: 54,
                     backgroundOverride: .rdCTA,
                     foregroundOverride: .white,
                     shadowOverride: .clear,
                     action: {
                         if reportQuotaExhausted && !(options.kind == .riskAnalysis && hasFreeRiskAnalysisTrial) {
                             if accessTier == .pro {
                                 onClose()
                             } else {
                                 onPaywall()
                             }
                             return
                         }
                         if options.kind == .riskAnalysis, riskAnalysisLocked {
                             onPaywall()
                             return
                         }
                         if options.kind == .riskAnalysis, outputFormat == .excel, let onGenerateExcel {
                             onGenerateExcel()
                         } else {
                             onGenerate()
                         }
                     })
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 10)
                .background(Color.rdPaper.opacity(0.98))
                .rdCardShadow(colorScheme: colorScheme, radius: 5, x: 7, y: 9)
                .accessibilityIdentifier("report.settings.generate")
        }
    }

    private var reportTypeSection: some View {
        VStack(spacing: 10) {
            reportKindRow(
                kind: .standard,
                title: "Standart Rapor",
                subtitle: standardReportSubtitle,
                icon: "doc.richtext",
                locked: options.kind == .standard && standardReportLocked
            )
            VStack(spacing: 0) {
                if hasFreeRiskAnalysisTrial {
                    freeRiskAnalysisTrialRibbon
                        .padding(.bottom, -1)
                }
                reportKindRow(
                    kind: .riskAnalysis,
                    title: "Risk Analizi Tablosu",
                    subtitle: riskAnalysisSubtitle,
                    icon: "tablecells",
                    locked: riskAnalysisLocked
                )
            }
        }
    }

    private var standardReportSubtitle: String {
        if options.kind == .standard, reportQuotaExhausted {
            return quotaExceededSubtitle
        }
        return "Hızlı Uygunsuzluk Raporu, ek bilgi girmeden oluşturulur."
    }

    private var riskAnalysisSubtitle: String {
        if hasFreeRiskAnalysisTrial {
            return "Tebrikler! Bir tane risk analizi oluşturma hakkı tanımlandı. Hemen deneyebilirsin."
        }
        if accessTier == .free {
            return "Bir kez tanımlanan hakkını kullandın. Risk analizi tabloları Plus ile devam eder."
        }
        if reportQuotaExhausted { return quotaExceededSubtitle }
        return "Fine-Kinney veya 5×5 Matris Metodu PDF ve Excel çıktısı, ayrıca özelleştirilebilir alanlar."
    }

    private var quotaExceededSubtitle: String {
        switch accessTier {
        case .free:
            return "Bugünkü standart rapor hakkın doldu. Hakların yarın yenilenir."
        case .plus:
            return "Plus aylık rapor limitin doldu. Pro ile limiti artırabilirsin."
        case .pro:
            return "Pro aylık rapor limitin doldu. Yeni rapor için gelecek ayı beklemelisin."
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
                        presentationDetent = .height(430)
                    } else {
                        presentationDetent = .large
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: locked ? 10 : 0) {
                HStack(spacing: 14) {
                    Image(systemName: locked ? (reportQuotaExhausted ? "exclamationmark.triangle.fill" : "lock.fill") : icon)
                        .font(.system(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                        .foregroundStyle(active ? Color.white : locked ? lockedIconForeground : Color.rdGreenDark)
                        .frame(width: 58, height: 58)
                        .background(active ? Color.rdGreen : locked ? lockedIconBackground : Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            if kind == .riskAnalysis, shouldShowRiskAnalysisStatusBadge {
                                riskAnalysisStatusBadge
                            }
                        }
                        Text(subtitle)
                            .font(.system(size: RDFontScale.size(13.5), design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: active ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: RDFontScale.size(24), weight: .bold, design: .rounded))
                        .foregroundStyle(active ? Color.rdGreen : Color.rdSlate.opacity(0.32))
                }

                if locked && active && kind == .riskAnalysis {
                    riskAnalysisPreview
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, active ? 18 : 16)
            .background(active ? Color.rdGreenSoft.opacity(0.65) : locked ? lockedCardBackground : Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(active ? Color.rdGreen.opacity(0.55) : locked ? lockedCardStroke : Color.rdLine, lineWidth: active ? 1.4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: active ? Color.rdGreen.opacity(0.12) : Color.clear, radius: 14, x: 0, y: 8)
        }
        .frame(minHeight: active && locked && kind == .riskAnalysis ? 286 : 104)
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityIdentifier("report.settings.kind.\(kind.rawValue)")
    }

    @ViewBuilder
    private var riskAnalysisStatusBadge: some View {
        if hasFreeRiskAnalysisTrial {
            EmptyView()
        } else if accessTier == .free || !canUseRiskAnalysis {
            RDTierBadge(tier: .plus, small: true)
                .scaleEffect(0.82)
        } else if reportQuotaExhausted {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: RDFontScale.size(8), weight: .bold, design: .rounded))
                Text("LİMİT DOLDU")
                    .font(.system(size: RDFontScale.size(8), weight: .heavy, design: .rounded))
                    .tracking(0.3)
            }
            .padding(.horizontal, 6)
            .frame(height: 18)
            .foregroundStyle(Color.rdCriticalText)
            .background(Color.rdCriticalBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var freeRiskAnalysisTrialRibbon: some View {
        HStack(spacing: 9) {
            Image(systemName: "gift.fill")
                .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                .foregroundStyle(SubscriptionTier.plus.accentTextColor)
                .frame(width: 28, height: 28)
                .background(Color.rdWhite.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            Text("Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!")
                .font(.system(size: RDFontScale.size(13.5), weight: .bold, design: .rounded))
                .foregroundStyle(SubscriptionTier.plus.accentTextColor)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    SubscriptionTier.plus.accentSoftColor.opacity(0.98),
                    Color.rdWhite.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SubscriptionTier.plus.accentColor.opacity(0.34), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan.")
    }

    private var riskAnalysisPreview: some View {
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
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(reportQuotaExhausted ? Color.rdCriticalText : SubscriptionTier.plus.accentTextColor)
                .frame(width: 26, height: 26)
                .background(reportQuotaExhausted ? Color.rdCriticalBg : SubscriptionTier.plus.accentSoftColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: RDFontScale.size(11.5), weight: .bold, design: .rounded))
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
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: RDFontScale.size(11.5), weight: .semibold, design: .rounded))
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
            settingsCardSection(title: "Dosya türü", icon: "doc.on.doc.fill") {
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
                                        .font(.system(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                                    VStack(spacing: 2) {
                                        Text(format.title)
                                            .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                                        Text(format.subtitle)
                                            .font(.system(size: RDFontScale.size(10), design: .rounded))
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
        settingsCardSection(title: "Risk analiz metodu", icon: "function") {
            HStack(spacing: 8) {
                ForEach(RiskMethod.allCases) { method in
                    let active = options.method == method
                    Button {
                        options.method = method
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 4) {
                            Text(method.label)
                                .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
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

    private var languageSection: some View {
        settingsSection(title: RDLocalization.shared.text(.reportLanguageSection, language: options.language)) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(RDLanguage.supportedCases) { language in
                    optionRow(
                        title: language.title,
                        subtitle: RDLocalization.shared.text(.reportLanguageTurkishSubtitle, language: language),
                        icon: language.icon,
                        active: options.language == language
                    ) {
                        options.language = language
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }

                Text(RDLocalization.shared.text(.reportLanguageFutureNote, language: options.language))
                    .font(.system(size: RDFontScale.size(11.5), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var companySelectionSection: some View {
        settingsSection(title: "RAPOR FİRMASI") {
            if accessTier.isPaid {
                Button {
                    showCompanyPicker = true
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedCompany == nil ? "building.2.crop.circle" : "building.2.fill")
                            .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                            .foregroundStyle(selectedCompany == nil ? Color.rdSlate : Color.rdGreenDark)
                            .frame(width: 40, height: 40)
                            .background(selectedCompany == nil ? Color.rdFog : Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedCompany?.name ?? "Firma seçmeden devam et")
                                .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                                .lineLimit(1)
                            Text(selectedCompany?.listSubtitle ?? "Arşiv, filtre ve firma bazlı rapor için firma seçebilir veya hızlıca ekleyebilirsin.")
                                .font(.system(size: RDFontScale.size(12), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .lineLimit(2)
                        }
                        Spacer()
                        if selectedCompany != nil {
                            Text("Değiştir")
                                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdGreenDark)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                    .padding(12)
                    .background(Color.rdWhite)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("report.settings.company_select")
            } else {
                Button {
                    onPaywall()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                            .foregroundStyle(SubscriptionTier.plus.accentTextColor)
                            .frame(width: 38, height: 38)
                            .background(SubscriptionTier.plus.accentSoftColor)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Firma bazlı rapor Plus ve Pro’da")
                                .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text("Logo, tehlike sınıfı ve firma arşivi için yükselt.")
                                .font(.system(size: RDFontScale.size(12), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(SubscriptionTier.plus.accentTextColor)
                    }
                    .padding(12)
                    .background(Color.rdWhite)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(SubscriptionTier.plus.accentColor.opacity(0.28), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func applyCompanyToOptions(_ company: Company?) {
        options.companyID = company?.id
        if let company {
            options.companyName = company.name
            options.companyInfo = company.reportInfoText
        } else {
            options.companyName = profile?.companyName ?? ""
            options.companyInfo = profile?.phone ?? ""
        }
    }

    private var selectedCheckmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
            .foregroundStyle(Color.rdGreen)
            .background(Circle().fill(Color.rdWhite))
    }

    private var identitySection: some View {
        settingsCardSection(title: "Hazırlayan bilgileri", icon: "person.text.rectangle.fill") {
            VStack(spacing: 10) {
                labeledField("Hazırlayan", text: $options.preparedBy, placeholder: profile?.displayName ?? "Ad Soyad", identifier: "report.settings.prepared_by")
                labeledField("Unvan", text: $options.preparedTitle, placeholder: profile?.title ?? "İSG Uzmanı", identifier: "report.settings.prepared_title")
                labeledField("Belge no", text: $options.certificateNumber, placeholder: profile?.certificateNumber ?? "Sertifika / belge no", identifier: "report.settings.certificate")
            }
        }
    }

    private var reportOverridesSection: some View {
        settingsSection(title: "BU RAPORA ÖZEL DÜZENLE") {
            VStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        showReportOverrides.toggle()
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdGreenDark)
                            .frame(width: 38, height: 38)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 11))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tek seferlik firma bilgisi veya logo")
                                .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(overrideSummaryText)
                                .font(.system(size: RDFontScale.size(12), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .rotationEffect(.degrees(showReportOverrides ? 180 : 0))
                    }
                    .padding(12)
                    .background(Color.rdWhite)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                if showReportOverrides {
                    VStack(spacing: 10) {
                        labeledField("Firma adı", text: $options.companyName, placeholder: selectedCompany?.name ?? profile?.companyName ?? "Firma adı", identifier: "report.settings.company_name")
                        labeledField("Firma bilgisi", text: $options.companyInfo, placeholder: selectedCompany?.reportInfoText ?? profile?.phone ?? "Telefon veya kısa bilgi", identifier: "report.settings.company_info")
                        companyLogoOverrideCard
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var overrideSummaryText: String {
        if selectedCompany != nil {
            return "Seçili firma korunur; sadece bu raporun görünen metinlerini veya logosunu değiştirebilirsin."
        }
        return "Firma eklemeden yalnızca bu raporda görünecek firma adı, bilgi veya logo girebilirsin."
    }

    private var companyLogoOverrideCard: some View {
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
                        .font(.system(size: RDFontScale.size(24), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .frame(width: 68, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(companyLogo == nil ? "Logo seçilmedi" : "Logo rapora eklenecek")
                    .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(selectedCompany == nil ? "Firma eklemeden bu rapora özel logo seçebilirsin." : "Seçili firma logosu korunur; istersen bu rapor için farklı logo seçebilirsin.")
                    .font(.system(size: RDFontScale.size(12), design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                Image(systemName: "plus")
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
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

    private func settingsCardSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 30, height: 30)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(title)
                    .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.rdBlack.opacity(0.035), radius: 12, x: 0, y: 6)
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? Color.rdGreenDark : Color.rdSlate)
                    .frame(width: 38, height: 38)
                    .background(active ? Color.rdGreenSoft : Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: RDFontScale.size(18), weight: .semibold, design: .rounded))
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

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String, identifier: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
            TextField(placeholder, text: text)
                .font(.system(size: RDFontScale.size(14), weight: .medium, design: .rounded))
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
                .accessibilityIdentifier(identifier ?? "report.settings.field.\(title)")
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

    private var requiredTier: SubscriptionTier {
        switch preview.level {
        case .critical, .high:
            return .pro
        case .medium, .low, .unknown:
            return .plus
        }
    }

    private var cardTint: Color {
        requiredTier.accentColor
    }

    private var cardTintSoft: Color {
        requiredTier.accentSoftColor
    }

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
                            .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                        Text(preview.hint)
                            .font(.system(size: compact ? 11 : 11.5, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.rdSlate.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RDTierBadge(tier: requiredTier, small: true)
                    .scaleEffect(0.78)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 9 : 11)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardTintSoft.opacity(compact ? 0.28 : 0.34))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(cardTint.opacity(compact ? 0.22 : 0.32), lineWidth: 1)
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
    let currentTier: SubscriptionTier
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
                            .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RDChip(level: band.level, label: band.label)
                    }
                    Text(finding.description)
                        .font(.system(size: RDFontScale.size(13), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    scoreBlock(band: band, score: score, max: max)

                    actionBlock

                    rootCauseBlock

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
                    .font(.system(size: RDFontScale.size(18), weight: .heavy, design: .monospaced))
                    .lineLimit(1)
                Text(method == .fineKinney ? "F-KINNEY" : "5×5")
                    .font(.system(size: RDFontScale.size(8), weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .opacity(0.85)
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(.white)
            .background(band.color)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(band.label)
                    .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
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
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
            Text("Önlem / Kontrol tedbirleri")
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)

            ForEach(finding.controlMeasures.indices, id: \.self) { index in
                let measure = finding.controlMeasures[index]
                (
                    Text("\(measure.displayTitle): ")
                        .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded)) +
                    Text(measure.text)
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
                )
                .foregroundStyle(Color.rdGraphite)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdGreenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var rootCauseBlock: some View {
        if currentTier.isPaid,
           !finding.rootCause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                    .foregroundStyle(SubscriptionTier.plus.accentTextColor)
                    .padding(.top, 2)
                (
                    Text("Kök neden · ").font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded)) +
                    Text(finding.rootCause).font(.system(size: RDFontScale.size(12), design: .rounded))
                )
                .foregroundStyle(Color.rdGraphite)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SubscriptionTier.plus.accentSoftColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func findingMetaCards(band: RiskBand) -> some View {
        let referencesTier = requiredTier(for: band.level)
        let referencesUnlocked = currentTier.includes(referencesTier)
        return HStack(alignment: .top, spacing: 8) {
            infoCard(
                icon: "checkmark.seal.fill",
                title: "Plan",
                value: band.action,
                tint: band.color
            )
            infoCard(
                icon: referencesUnlocked ? "books.vertical.fill" : "lock.fill",
                title: "Mevzuat",
                value: referencesUnlocked ? (finding.references.isEmpty ? "Kontrol edilmeli" : finding.references) : "\(referencesTier.title)'ta açık",
                tint: referencesUnlocked ? Color.rdGreenDark : referencesTier.accentTextColor
            )
        }
    }

    private func requiredTier(for _: RiskLevel) -> SubscriptionTier {
        .plus
    }

    private func infoCard(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: RDFontScale.size(8), weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(Color.rdSlate)
                Text(value)
                    .font(.system(size: RDFontScale.size(10.5), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdGraphite)
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
                .font(.system(size: RDFontScale.size(10), weight: .semibold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(10), weight: .semibold, design: .rounded))
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
