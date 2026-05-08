import SwiftUI
import UIKit
import PhotosUI

struct ResultView: View {
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
    @State private var isGeneratingPDF: Bool = false
    @State private var pdfProgress: Double = 0
    @State private var pdfProgressTask: Task<Void, Never>?
    @State private var pdfError: String?
    @State private var shareItem: ShareItem?
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
                        methodFootnote
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdPaper)
        .overlay {
            if isGeneratingPDF {
                PDFGenerationOverlay(progress: pdfProgress)
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isGeneratingPDF)
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
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showReportSettings) {
            ReportSettingsSheet(
                options: $reportOptions,
                companyLogo: $reportCompanyLogo,
                profile: app.profile,
                onGenerate: {
                    showReportSettings = false
                    generateAndSharePDF(options: reportOptions)
                },
                onClose: { showReportSettings = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("PDF Hatası", isPresented: Binding(
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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            roundIconButton(systemName: "chevron.left", action: onClose)
            Spacer()
            Text("Analiz Sonucu")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            roundIconButton(systemName: "square.and.arrow.up") {
                generateAndSharePDF()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func roundIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
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
            HStack(alignment: .top, spacing: 12) {
                ResultPhotoThumbnail(image: localPreviewImage, path: photoPath, cornerRadius: 12)
                    .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysisTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rdBlack)
                    Text("\(formattedDate) · \(canvasLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.rdSlate)
                        .padding(.bottom, 6)

                    HStack(spacing: 6) {
                        metaChip("\(findings.count) bulgu", bg: .rdFog, fg: .rdCharcoal)
                        confidenceChip
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
                    .font(.system(size: 10, weight: .bold))
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
                    VStack(spacing: 2) {
                        Text(m.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                        Text("R = \(m.formula)")
                            .rdMono(size: 10, weight: .medium)
                            .foregroundStyle(Color.rdSlate)
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
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.rdSlate)

                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(scoreText(topScore, method: method))
                                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                                .foregroundStyle(topBand.color)
                                .tracking(-0.5)
                            Text("· en yüksek risk")
                                .rdMono(size: 12)
                                .foregroundStyle(Color.rdSlate)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(topBand.label)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(topBand.color)
                        .background(topBand.color.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 8)

                    HStack(alignment: .bottom, spacing: 6) {
                        countBar(level: .critical, count: counts[.critical] ?? 0)
                        countBar(level: .high,     count: counts[.high] ?? 0)
                        countBar(level: .medium,   count: counts[.medium] ?? 0)
                        countBar(level: .low,      count: counts[.low] ?? 0)
                    }
                }

                Text(aiSummary(totalScore: totalScore))
                    .font(.system(size: 12))
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
                .font(.system(size: 8, weight: .bold))
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.rdGreenDark)
                    Text("Tehlike tespit edilmedi")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                }

                Text("Bu analiz için raporlanabilir bir uygunsuzluk bulunmadı. Görsel veya metin yeterince açık değilse farklı bir açıdan tekrar tarama yapılabilir.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tespit edilen tehlikeler · risk hesaplaması".uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)
                .padding(.leading, 4)

            ForEach(Array(sortedFindings.enumerated()), id: \.element.id) { index, finding in
                FindingCard(finding: finding, index: index + 1, method: method) {
                    selectedFinding = finding
                }
            }
        }
    }

    // MARK: - Pro upsell

    private var proUpsellCard: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                RDProBadge()
                Text("Detaylı risk analizi tablosu")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 10)
                Text("Olasılık × Etki matrisi, kalıcı kontrol önerileri ve denetim notları PRO ile açılır.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)
                RDButton(title: "PRO'yu keşfet", style: .detect) { showPaywall = true }
                    .padding(.top, 10)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rdBlack)
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            RDButton(
                title: isGeneratingPDF ? "PDF hazırlanıyor..." : "Standart PDF",
                style: .primary,
                icon: isGeneratingPDF ? "hourglass" : "arrow.down.to.line",
                height: 56,
                action: { generateAndSharePDF() }
            )
            .frame(maxWidth: .infinity)
            .layoutPriority(2)

            reportSettingsButton
        }
    }

    private var reportSettingsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if app.isPro {
                reportOptions = defaultReportOptions(kind: reportOptions.kind == .standard ? .riskAnalysis : reportOptions.kind)
                showReportSettings = true
            } else {
                showPaywall = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 34)
                        .foregroundStyle(app.isPro ? Color.rdBlack : Color.rdSlate)
                    Text(app.isPro ? "Risk Analizi" : "Ayarlar")
                        .font(.system(size: app.isPro ? 9.5 : 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(app.isPro ? Color.rdBlack : Color.rdHighText)
                }
                .frame(width: 86, height: 56)
                .background(app.isPro ? Color.rdFog : Color.rdHighBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(app.isPro ? Color.rdLine : Color(hex: "#F6C343"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7, weight: .heavy))
                    Text("PRO")
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(0.4)
                }
                .padding(.horizontal, 5)
                .frame(height: 15)
                .foregroundStyle(Color(hex: "#3A2A00"))
                .background(Color(hex: "#FFE08A"))
                .overlay(
                    Capsule()
                        .stroke(Color(hex: "#F6C343"), lineWidth: 1)
                )
                .clipShape(Capsule())
                .offset(x: 6, y: -6)
            }
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(app.isPro ? "Rapor ayarları" : "Pro rapor ayarları")
    }

    private var methodFootnote: some View {
        Text("\(method.fullName) · risk değerlendirme şablonu")
            .rdMono(size: 11)
            .foregroundStyle(Color.rdSlate)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func scoreText(_ value: Double, method: RiskMethod) -> String {
        switch method {
        case .fineKinney: return "\(Int(value))"
        case .matrix5x5:  return "\(Int(value))"
        }
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

    private func generateAndSharePDF(options: PDFReportOptions? = nil) {
        guard !isGeneratingPDF else { return }
        guard let bundle else {
            pdfError = "PDF oluşturmak için tamamlanmış bir analiz bulunamadı."
            return
        }

        startPDFProgress()
        Task {
            do {
                let reportImage = try await loadReportImage()
                advancePDFProgress(to: 0.23)
                let resolvedOptions = options ?? PDFReportOptions.standard(method: method)
                let input = PDFReportService.ReportInput(
                    bundle: bundle,
                    findings: sortedFindings(for: resolvedOptions.method),
                    profile: app.profile,
                    image: reportImage,
                    companyLogo: options == nil ? nil : reportCompanyLogo,
                    options: resolvedOptions
                )
                let url = try await PDFReportService.shared.generateAsync(input: input)
                advancePDFProgress(to: 0.71)
                if let userID = app.auth.session?.user.id {
                    do {
                        _ = try await AnalysisService.shared.storeReport(
                            userID: userID,
                            bundle: bundle,
                            fileURL: url,
                            kind: resolvedOptions.kind,
                            method: resolvedOptions.method
                        )
                        advancePDFProgress(to: 0.92)
                    } catch {
                        stopPDFGenerationWithError("PDF oluşturuldu ancak rapor arşivine kaydedilemedi: \(error.localizedDescription)")
                        return
                    }
                }
                await completePDFGeneration(url: url)
            } catch {
                stopPDFGenerationWithError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func startPDFProgress() {
        pdfProgressTask?.cancel()
        pdfProgress = 0.07
        isGeneratingPDF = true

        pdfProgressTask = Task { @MainActor in
            let waypoints: [Double] = [0.12, 0.18, 0.23, 0.31, 0.38, 0.46, 0.54, 0.61, 0.68, 0.71, 0.76, 0.81, 0.86, 0.90]
            for point in waypoints {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                advancePDFProgress(to: point)
            }

            while !Task.isCancelled && pdfProgress < 0.94 {
                try? await Task.sleep(nanoseconds: 850_000_000)
                guard !Task.isCancelled else { return }
                advancePDFProgress(to: min(pdfProgress + 0.01, 0.94))
            }
        }
    }

    @MainActor
    private func advancePDFProgress(to value: Double) {
        guard isGeneratingPDF else { return }
        let nextValue = max(pdfProgress, min(max(value, 0), 0.98))
        withAnimation(.easeInOut(duration: 0.28)) {
            pdfProgress = nextValue
        }
    }

    @MainActor
    private func completePDFGeneration(url: URL) async {
        pdfProgressTask?.cancel()
        pdfProgressTask = nil
        withAnimation(.easeInOut(duration: 0.24)) {
            pdfProgress = 0.98
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        withAnimation(.easeInOut(duration: 0.22)) {
            pdfProgress = 1
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
        shareItem = ShareItem(url: url)
        isGeneratingPDF = false
        pdfProgress = 0
    }

    @MainActor
    private func stopPDFGenerationWithError(_ message: String) {
        pdfProgressTask?.cancel()
        pdfProgressTask = nil
        pdfError = message
        isGeneratingPDF = false
        pdfProgress = 0
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
}

// MARK: - Report Settings

struct ReportSettingsSheet: View {
    @Binding var options: PDFReportOptions
    @Binding var companyLogo: UIImage?
    let profile: UserProfile?
    let onGenerate: () -> Void
    let onClose: () -> Void
    @State private var selectedLogoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    proHeader
                    reportTypeSection
                    methodSection
                    identitySection
                    companyLogoSection

                    RDButton(title: "Bu ayarlarla PDF oluştur",
                             style: .detect,
                             icon: "doc.richtext.fill",
                             height: 54,
                             action: onGenerate)
                        .padding(.top, 4)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.rdPaper)
            .navigationTitle("Rapor Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat", action: onClose)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }

    private var proHeader: some View {
        RDCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color(hex: "#F5B700"))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: "#FFF7D6"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("PRO rapor çıktısı")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.rdBlack)
                        RDProBadge(small: true)
                    }
                    Text("Standart PDF yanında firma bilgili ve metoda özel detaylı risk analizi çıktısı oluşturabilirsin.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var reportTypeSection: some View {
        settingsSection(title: "RAPOR TİPİ") {
            VStack(spacing: 8) {
                ForEach(PDFReportKind.allCases) { kind in
                    optionRow(
                        title: kind.title,
                        subtitle: kind.subtitle,
                        icon: kind == .standard ? "doc.text" : "tablecells",
                        active: options.kind == kind
                    ) {
                        options.kind = kind
                    }
                }
            }
        }
    }

    private var methodSection: some View {
        settingsSection(title: "RİSK METODU") {
            HStack(spacing: 8) {
                ForEach(RiskMethod.allCases) { method in
                    let active = options.method == method
                    Button {
                        options.method = method
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 4) {
                            Text(method.label)
                                .font(.system(size: 13, weight: .bold))
                            Text("R = \(method.formula)")
                                .rdMono(size: 10)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
                        .background(active ? Color.rdWhite : Color.rdFog)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(active ? Color.rdBlack : Color.rdLine, lineWidth: active ? 1.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var identitySection: some View {
        settingsSection(title: "RAPOR BİLGİLERİ") {
            VStack(spacing: 10) {
                labeledField("Hazırlayan", text: $options.preparedBy, placeholder: profile?.displayName ?? "Ad Soyad")
                labeledField("Firma", text: $options.companyName, placeholder: profile?.companyName ?? "Firma adı")
            }
        }
    }

    private var companyLogoSection: some View {
        settingsSection(title: "FİRMA LOGOSU") {
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
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(width: 68, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(companyLogo == nil ? "Logo seçilmedi" : "Logo rapora eklenecek")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    Text("Seçilen logo bu PDF çıktısında kullanılır. Profilde kalıcı logo kaydı sonraki adımda eklenecek.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
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
                .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(active ? Color.rdGreenDark : Color.rdSlate)
                    .frame(width: 38, height: 38)
                    .background(active ? Color.rdGreenSoft : Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rdSlate)
            TextField(placeholder, text: text)
                .font(.system(size: 14, weight: .medium))
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

// MARK: - FindingCard

struct FindingCard: View {
    let finding: Finding
    let index: Int
    let method: RiskMethod
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.rdBlack)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RDChip(level: band.level, label: band.label)
                    }
                    Text(finding.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    scoreBlock(band: band, score: score, max: max)

                    actionBlock

                    HStack {
                        Text(band.action)
                            .rdMono(size: 11)
                        Spacer()
                        Text(finding.references)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.rdSlate)
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
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .opacity(0.85)
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(.white)
            .background(band.color)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(band.label)
                    .font(.system(size: 12, weight: .bold))
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.rdGreenDark)
                .padding(.top, 2)
            (
                Text("Önlem · ").font(.system(size: 12, weight: .bold)) +
                Text(finding.action).font(.system(size: 12))
            )
            .foregroundStyle(Color.rdGraphite)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdGreenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ResultPhotoThumbnail: View {
    let image: UIImage?
    let path: String?
    var cornerRadius: CGFloat
    @State private var remoteImage: UIImage?
    @State private var loadedPath: String?

    var body: some View {
        ZStack {
            if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AnalysisThumbnail(path: nil, cornerRadius: cornerRadius)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
                .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 10, weight: .semibold))
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
