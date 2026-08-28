import SwiftUI
import UIKit

/// Shared typography contract for the result hub, item details and report
/// configuration surfaces. Keeping a single mapping prevents the same flow
/// from mixing Mulish with the system rounded face.
enum ResultTypography {
    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom(postScriptName(for: weight), size: size)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        if weight == .black { return "Mulish-Black" }
        if weight == .heavy { return "Mulish-ExtraBold" }
        if weight == .bold { return "Mulish-Bold" }
        if weight == .semibold { return "Mulish-SemiBold" }
        if weight == .medium { return "Mulish-Medium" }
        return "Mulish-Regular"
    }
}

/// Native SwiftUI projection of the approved 440 × 956 result-hub reference.
/// Product data and permissions remain authoritative while the supplied HTML
/// defines layout, hierarchy and interaction styling.
struct AnalysisResultHubView: View {
    let hub: AnalysisResultHubResponse
    let analysisID: UUID
    let language: RDLanguage
    let analysisTitle: String
    let analysisSector: String?
    let analysisPhotos: [ResultPhotoItem]
    @Binding var method: RiskMethod
    let onOpenAnalysisPhoto: (UIImage) -> Void
    let onOpenFinding: (FindingRow) -> Void
    let onEditFinding: (FindingRow) -> Void
    let onDeleteFinding: (FindingRow) -> Void
    let onPaywall: (AnalysisResultSectionID, UUID) -> Void
    let onCreateReport: (AnalysisResultSectionID, [UUID], String) -> Void
    let onEditNotebook: (AnalysisResultHubItem, String, String) -> Void
    let onSuppressNotebook: (AnalysisResultHubItem) -> Void

    @State private var selectedSection: AnalysisResultSectionID = .riskAnalysis
    @State private var selections: [AnalysisResultSectionID: Set<UUID>] = [:]
    @State private var reactions: [UUID: AnalysisItemReaction] = [:]
    @State private var detailItem: AnalysisResultHubItem?
    @State private var pendingDislike: AnalysisResultHubItem?
    @State private var editingNotebook: AnalysisResultHubItem?
    @State private var pendingNotebookSuppression: AnalysisResultHubItem?
    @State private var notebookFindingDraft = ""
    @State private var notebookRecommendationDraft = ""
    @State private var reportSheetPresented = false
    @State private var reportKind: ReferenceReportKind?
    @State private var reportFormat = "pdf"
    @State private var reportSheetDetent: PresentationDetent = .height(ReferenceReportSheetLayout.compactHeight)
    @State private var funnelSessionID = UUID()

    private let green = Color(hex: "#35774A")
    private let greenDark = Color(hex: "#2E6B41")
    private let greenMuted = Color(hex: "#5D9670")
    private let lime = Color(hex: "#E8FAC6")
    private let ink = Color(hex: "#1A1A1A")
    private let muted = Color(hex: "#6D6D6D")
    private let summaryStart = Color(hex: "#3F6FA8")
    private let summaryMid = Color(hex: "#2F5183")
    private let summaryEnd = Color(hex: "#1F3557")

    private var activeSection: AnalysisResultSection {
        hub.sections.first(where: { $0.id == selectedSection })
            ?? AnalysisResultSection(
                id: selectedSection,
                access: .full,
                count: 0,
                canEdit: false,
                canReport: false,
                items: []
            )
    }

    private var selectedIDs: Set<UUID> { selections[selectedSection] ?? [] }
    private var isFreeTier: Bool { (hub.tier ?? "").lowercased() == "free" }
    private var reportSheetDetents: Set<PresentationDetent> {
        if selectedSection == .riskAnalysis {
            return [ReferenceReportSheetLayout.compactDetent, ReferenceReportSheetLayout.expandedDetent]
        }
        return [ReferenceReportSheetLayout.compactDetent]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        sectionContent
                            .id(selectedSection)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                    } header: {
                        sectionSelector
                    }
                }
            }
            .background(Color.white)
            reportBar
        }
        .background(Color.white.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .bottom)
        .task(id: hub.analysisID) {
            initializeState()
            await AnalysisResultHubService.shared.recordEvent(
                analysisID: analysisID,
                language: language,
                name: "result_screen_viewed",
                section: selectedSection,
                funnelSessionID: funnelSessionID
            )
        }
        .sheet(item: $detailItem) { item in
            ReferenceHubDetailView(
                item: item,
                section: selectedSection,
                language: language,
                onEdit: { edit(item) },
                onDelete: { delete(item) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $reportSheetPresented) {
            ReferenceReportSheet(
                section: selectedSection,
                language: language,
                selectedCount: selectedIDs.count,
                totalCount: activeSection.count,
                isFreeTier: isFreeTier,
                canReport: activeSection.canReport,
                method: $method,
                reportKind: $reportKind,
                reportFormat: $reportFormat,
                selectedDetent: $reportSheetDetent,
                onClose: { reportSheetPresented = false },
                onUpgrade: {
                    reportSheetPresented = false
                    onPaywall(selectedSection, funnelSessionID)
                },
                onGenerate: {
                    let format = reportKind == .standard ? "pdf" : reportFormat
                    reportSheetPresented = false
                    onCreateReport(selectedSection, Array(selectedIDs), format)
                }
            )
            .presentationDetents(reportSheetDetents, selection: $reportSheetDetent)
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $editingNotebook) { item in notebookEditor(item) }
        .alert(copy("Defter kaydı gizlensin mi?", "Hide this Safety Log entry?"), isPresented: Binding(
            get: { pendingNotebookSuppression != nil },
            set: { if !$0 { pendingNotebookSuppression = nil } }
        )) {
            Button(copy("Vazgeç", "Cancel"), role: .cancel) { pendingNotebookSuppression = nil }
            Button(copy("Gizle", "Hide"), role: .destructive) {
                guard let item = pendingNotebookSuppression else { return }
                pendingNotebookSuppression = nil
                onSuppressNotebook(item)
            }
        } message: {
            Text(copy(
                "Kayıt geri alınabilir biçimde gizlenecek; geçmiş raporlar değişmeyecek.",
                "The entry will be hidden reversibly; previous report snapshots will not change."
            ))
        }
        .confirmationDialog(
            copy("Neyi geliştirebiliriz?", "What can we improve?"),
            isPresented: Binding(
                get: { pendingDislike != nil },
                set: { if !$0 { pendingDislike = nil } }
            ),
            titleVisibility: .visible
        ) {
            dislikeReasonButton(copy("Yanlış tespit", "Incorrect detection"), code: "incorrect_detection")
            dislikeReasonButton(copy("Eksik bağlam", "Missing context"), code: "missing_context")
            dislikeReasonButton(copy("Yanlış skor", "Incorrect score"), code: "wrong_score")
            dislikeReasonButton(copy("Yetersiz / yanlış önlem", "Insufficient or incorrect control"), code: "wrong_recommendation")
            dislikeReasonButton(copy("Tekrar içerik", "Duplicate content"), code: "duplicate")
            dislikeReasonButton(copy("Metin anlaşılır değil", "Unclear wording"), code: "unclear_text")
            Button(copy("Neden belirtmeden gönder", "Send without a reason")) { submitPendingDislike(reason: nil) }
            Button(copy("Vazgeç", "Cancel"), role: .cancel) { pendingDislike = nil }
        }
    }

    // MARK: Connected section selector

    private var sectionSelector: some View {
        GeometryReader { proxy in
            let count = max(1, hub.sections.count)
            let gaps = CGFloat(max(0, count - 1)) * 6.7
            let fitted = (proxy.size.width - 40 - gaps) / CGFloat(min(count, 3))
            let tabWidth = count <= 3 ? fitted : max(116, fitted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6.7) {
                    ForEach(hub.sections) { section in
                        sectionTab(section, width: tabWidth)
                    }
                }
                .padding(.horizontal, 20)
                .frame(minWidth: proxy.size.width, minHeight: 96, alignment: .bottomLeading)
            }
            // The shared rail belongs behind the tabs. The selected tab's white
            // bottom mask can then interrupt it and visually connect the tab to
            // the content surface, matching the approved reference.
            .background(alignment: .bottom) { Rectangle().fill(green).frame(height: 1.5) }
        }
        .frame(height: 96)
        .background(Color.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.hub.section_selector")
        .zIndex(20)
    }

    private func sectionTab(_ section: AnalysisResultSection, width: CGFloat) -> some View {
        let selected = selectedSection == section.id
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedSection = section.id }
            Task {
                await AnalysisResultHubService.shared.recordEvent(
                    analysisID: analysisID,
                    language: language,
                    name: "result_section_selected",
                    section: section.id,
                    funnelSessionID: funnelSessionID
                )
                if section.access == .teaser {
                    await AnalysisResultHubService.shared.recordEvent(
                        analysisID: analysisID,
                        language: language,
                        name: "locked_teaser_impression",
                        section: section.id,
                        funnelSessionID: funnelSessionID
                    )
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: sectionIcon(section.id))
                    .font(.system(size: 20, weight: .regular))
                Text(section.id.compactTitle(language: language))
                    .font(referenceFont(11.5, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("\(section.count) \(section.id.countLabel(language: language))")
                    .font(referenceFont(10, .semibold))
                    .foregroundStyle(greenMuted)
                    .lineLimit(1)
            }
            .foregroundStyle(greenDark)
            .frame(width: width, height: selected ? 84 : 72)
            .background(
                Group {
                    if selected { ConnectedTabFill(cornerRadius: 8).fill(Color.white) }
                    else { RoundedRectangle(cornerRadius: 6).fill(lime) }
                }
            )
            .overlay {
                if selected {
                    ConnectedTabBorder(cornerRadius: 8)
                        .stroke(green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(Color.white).frame(height: 2.5) }
            }
            .padding(.bottom, selected ? 0 : 8)
        }
        .buttonStyle(.plain)
        .zIndex(selected ? 2 : 1)
        .accessibilityLabel("\(section.id.title(language: language)), \(section.count) \(section.id.countLabel(language: language))")
        .accessibilityIdentifier("result.hub.section.\(section.id.rawValue)")
    }

    private func sectionIcon(_ id: AnalysisResultSectionID) -> String {
        switch id {
        case .riskAnalysis: return "exclamationmark.triangle"
        case .expertRecommendations: return "person.badge.shield.checkmark"
        case .approvedNotebook: return "book.closed"
        }
    }

    // MARK: Section content

    @ViewBuilder
    private var sectionContent: some View {
        if activeSection.items.isEmpty {
            emptyState.padding(.top, 18)
        } else {
            switch selectedSection {
            case .riskAnalysis: riskContent
            case .expertRecommendations: expertContent
            case .approvedNotebook: notebookContent
            }
        }
    }

    private var riskContent: some View {
        let premiumInsertionIndex = min(1, max(0, activeSection.items.count - 1))

        return VStack(spacing: 0) {
            riskSummary.padding(.top, 12)
            methodSelector.padding(.top, 9)
            analysisInfoCard.padding(.top, 13)
            selectionControls.padding(.top, 12).padding(.bottom, 20)
            LazyVStack(spacing: 34) {
                ForEach(Array(activeSection.items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 16) {
                        riskCard(item, position: index + 1)
                        if index == premiumInsertionIndex {
                            premiumRibbon
                        }
                    }
                }
            }
        }
    }

    private var expertContent: some View {
        VStack(spacing: 0) {
            nonRiskSummary.padding(.top, 12)
            selectionControls.padding(.top, 12).padding(.bottom, 26)
            LazyVStack(spacing: 34) {
                ForEach(Array(activeSection.items.enumerated()), id: \.element.id) { index, item in
                    expertCard(item, position: index + 1)
                }
            }
        }
    }

    private var notebookContent: some View {
        VStack(spacing: 0) {
            nonRiskSummary.padding(.top, 12)
            notebookPaper.padding(.top, 16)
        }
    }

    // MARK: Reference summaries

    private var riskSummary: some View {
        let counts = riskCounts
        let highest = activeSection.items.compactMap {
            method == .fineKinney ? $0.fkScore : $0.m5Score.map(Double.init)
        }.max() ?? 0
        let highestLevel = activeSection.items
            .map(riskLevel(for:))
            .max(by: { riskRank($0) < riskRank($1) }) ?? .unknown
        let maximumCount = max(1, counts.values.max() ?? 1)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(copy("TOPLAM BULGU", "TOTAL FINDINGS"))
                    .font(referenceFont(10, .heavy)).tracking(0.4).foregroundStyle(.white.opacity(0.88))
                Text("\(activeSection.count)")
                    .font(referenceFont(30, .black)).tracking(-1.4).foregroundStyle(.white)
            }
            Rectangle().fill(.white.opacity(0.26)).frame(width: 1, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy("EN YÜKSEK SKOR", "HIGHEST SCORE"))
                    .font(referenceFont(10, .heavy)).tracking(0.4).foregroundStyle(.white.opacity(0.88))
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(scoreText(highest)).font(referenceFont(22, .black)).tracking(-1)
                    Text(method == .fineKinney ? copy("puan", "points") : "/25")
                        .font(referenceFont(9.5, .bold)).foregroundStyle(.white.opacity(0.85))
                }
                Text(riskBandLabel(highestLevel))
                    .font(referenceFont(8, .heavy)).tracking(0.3)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(referenceRiskColor(highestLevel))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(copy("DAĞILIM", "DISTRIBUTION"))
                    .font(referenceFont(10, .heavy)).tracking(0.4).foregroundStyle(.white.opacity(0.88))
                HStack(alignment: .bottom, spacing: 7) {
                    distributionBar(.critical, count: counts[.critical] ?? 0, maximum: maximumCount)
                    distributionBar(.high, count: counts[.high] ?? 0, maximum: maximumCount)
                    distributionBar(.medium, count: counts[.medium] ?? 0, maximum: maximumCount)
                    distributionBar(.low, count: counts[.low] ?? 0, maximum: maximumCount)
                }
                .frame(height: 46, alignment: .bottom)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 87)
        .background(
            ZStack {
                LinearGradient(colors: [summaryStart, summaryMid, summaryEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.08)).frame(width: 84, height: 84).offset(x: 178, y: -35)
                Circle().fill(.white.opacity(0.05)).frame(width: 60, height: 60).offset(x: 90, y: 54)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(hex: "#142A4A").opacity(0.24), radius: 9, x: 4, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activeSection.count) \(copy("bulgu", "findings")), \(copy("en yüksek skor", "highest score")) \(scoreText(highest))")
    }

    private var nonRiskSummary: some View {
        let isExpert = selectedSection == .expertRecommendations
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: isExpert ? "lightbulb" : "book.closed")
                .font(.system(size: 20, weight: .regular)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(isExpert ? copy("Uzman görüşleri", "Expert recommendations") : copy("Onaylı defter", "Safety log"))
                        .font(referenceFont(14, .black)).foregroundStyle(.white)
                    premiumPill
                }
                Text(isExpert
                     ? copy("Her bulgu için uzman değerlendirmesi, düzeltici önlem ve önleyici kontrol tedbirleri.", "Expert assessment, corrective action and preventive controls for each finding.")
                     : copy("Analiz bulgularından üretilen, uzman değerlendirmesine sunulan defter taslakları.", "Safety log drafts projected from the analysis for expert review."))
                    .font(referenceFont(11, .medium)).foregroundStyle(.white.opacity(0.78)).lineSpacing(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                Text("\(activeSection.count)").font(referenceFont(26, .black)).tracking(-1.2)
                Text(selectedSection == .expertRecommendations ? copy("TOPLAM GÖRÜŞ", "TOTAL") : copy("TOPLAM ÖNERİ", "TOTAL"))
                    .font(referenceFont(9, .heavy)).tracking(0.4).foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(
            ZStack {
                LinearGradient(colors: [summaryStart, summaryMid, summaryEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.08)).frame(width: 84, height: 84).offset(x: 180, y: -32)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(hex: "#142A4A").opacity(0.24), radius: 9, x: 4, y: 8)
    }

    private func distributionBar(_ level: RiskLevel, count: Int, maximum: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(count)").font(referenceFont(10, .black)).foregroundStyle(.white)
            RoundedRectangle(cornerRadius: 3)
                .fill(summaryBarColor(level, active: count > 0))
                .frame(width: 11, height: max(2, CGFloat(count) / CGFloat(maximum) * 30))
            Text(shortRiskLabel(level))
                .font(referenceFont(8, .heavy)).tracking(0.2).foregroundStyle(.white.opacity(0.70))
        }
    }

    private func summaryBarColor(_ level: RiskLevel, active: Bool) -> Color {
        guard active else { return Color(hex: "#E8E8E8") }
        switch level {
        case .critical: return Color(hex: "#F0736A")
        case .high: return Color(hex: "#F0A55C")
        case .medium: return Color(hex: "#EFD677")
        case .low: return Color(hex: "#7FD3A0")
        case .unknown: return Color(hex: "#E8E8E8")
        }
    }

    // MARK: Risk preface

    private var methodSelector: some View {
        HStack(spacing: 8) {
            methodButton(.fineKinney, title: "Fine-Kinney", formula: "R = O × F × Ş")
            methodButton(.matrix5x5, title: copy("5x5 Matris", "5x5 Matrix"), formula: "R = O × Ş")
        }
    }

    private func methodButton(_ candidate: RiskMethod, title: String, formula: String) -> some View {
        let selected = method == candidate
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.16)) { method = candidate }
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .black)) }
                    Text(title).font(referenceFont(11.5, selected ? .heavy : .bold))
                }
                Text(formula).font(referenceFont(8.5, .bold)).tracking(0.2)
            }
            .foregroundStyle(selected ? greenDark : Color(hex: "#8A8A8A"))
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(selected ? Color(hex: "#F4FAEC") : Color(hex: "#FAFAFA"))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? green : Color(hex: "#E2E2E2"), lineWidth: selected ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: selected ? Color.black.opacity(0.08) : .clear, radius: 6, x: 3, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var analysisInfoCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(analysisTitle).font(referenceFont(16, .heavy)).foregroundStyle(ink).lineLimit(2)
                if let analysisSector, !analysisSector.isEmpty {
                    HStack(spacing: 4) {
                        Text(copy("Sektör:", "Sector:"))
                            .font(referenceFont(10.5, .bold)).foregroundStyle(Color(hex: "#9A9A9A"))
                        Text(analysisSector)
                            .font(referenceFont(10.5, .heavy)).foregroundStyle(greenDark).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(Array(analysisPhotos.prefix(3).enumerated()), id: \.element.id) { index, photo in
                    ResultPhotoThumbnail(
                        image: photo.image,
                        path: photo.path,
                        isTextAnalysis: false,
                        cornerRadius: 8,
                        onTap: onOpenAnalysisPhoto
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.09), radius: 4, x: 1, y: 3)
                    .accessibilityIdentifier("result.hub.analysis_photo.\(index + 1)")
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#F3F7F1"))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#D8E4D6"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.hub.analysis_info_card")
    }

    private var premiumRibbon: some View {
        Button { onPaywall(.riskAnalysis, funnelSessionID) } label: {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill").foregroundStyle(Color(hex: "#E0A828"))
                Text("PLUS").foregroundStyle(Color(hex: "#A67C12"))
                Image(systemName: "star.fill").foregroundStyle(green)
                Text("PRO").foregroundStyle(greenDark)
                Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1, height: 14)
                Text(copy("Derin Araştırma ve Gelişmiş Analiz", "Deep Research and Advanced Analysis"))
                    .foregroundStyle(Color(hex: "#5A5A5A")).lineLimit(1).minimumScaleFactor(0.72)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Color(hex: "#9A9A9A"))
            }
            .font(referenceFont(10.5, .heavy)).padding(.horizontal, 10).padding(.vertical, 7)
            .background(LinearGradient(colors: [Color(hex: "#FFF4DC"), Color(hex: "#FDFAF0"), Color(hex: "#EEF8EC")], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 7.5)).padding(1.5)
            .background(LinearGradient(colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("result.hub.premium_ribbon")
    }

    private var selectionControls: some View {
        HStack {
            Text(selectedCountText).font(referenceFont(10.5, .bold)).foregroundStyle(Color(hex: "#9A9A9A"))
            Spacer()
            if activeSection.access == .full {
                Button {
                    let all = Set(activeSection.items.map(\.id))
                    selections[selectedSection] = selectedIDs.count == all.count ? [] : all
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .black))
                        Text(selectedIDs.count == activeSection.items.count ? copy("Tümünü bırak", "Clear all") : copy("Tümünü seç", "Select all"))
                            .font(referenceFont(11.5, .heavy))
                    }
                    .foregroundStyle(greenDark)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedCountText: String {
        let unit: String
        switch selectedSection {
        case .riskAnalysis: unit = copy("bulgu", "findings")
        case .expertRecommendations: unit = copy("görüş", "recommendations")
        case .approvedNotebook: unit = copy("kayıt", "entries")
        }
        return "\(selectedIDs.count)/\(activeSection.count) \(unit) \(copy("seçili", "selected"))"
    }

    // MARK: Finding cards

    private func riskCard(_ item: AnalysisResultHubItem, position: Int) -> some View {
        let level = riskLevel(for: item)
        let score = method == .fineKinney ? item.fkScore : item.m5Score.map(Double.init)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(methodRiskBandLabel(for: item, fallback: level))
                        .font(referenceFont(10.5, .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(referenceRiskColor(level)).clipShape(RoundedRectangle(cornerRadius: 2))
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(score.map(scoreText) ?? "—").font(referenceFont(16, .black))
                        Text(method == .fineKinney ? copy("puan", "points") : "/25")
                            .font(referenceFont(10.5, .bold)).foregroundStyle(Color(hex: "#9A9A9A"))
                    }
                    Spacer()
                    if activeSection.access == .full { selectionControl(item) }
                }
                Text(item.displayTitle(language: language))
                    .font(referenceFont(15, .heavy)).foregroundStyle(ink).lineSpacing(1)
                    .padding(.top, 12).fixedSize(horizontal: false, vertical: true)
                Text(item.displayBody)
                    .font(referenceFont(12.5, .regular)).foregroundStyle(muted).lineSpacing(3)
                    .padding(.top, 8).lineLimit(activeSection.access == .teaser ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                featureTags(item).padding(.top, 12)
                if activeSection.access == .teaser { lockedContent(item).padding(.top, 12) }
            }
            .padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 16)
            if activeSection.access == .full { actionStrip(item) }
        }
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(green, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.10), radius: 7, x: 4, y: 6)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 25, weight: .regular)).foregroundStyle(referenceRiskColor(level))
                    .frame(width: 36, height: 36)
                Text("\(position) -").font(referenceFont(13, .black)).foregroundStyle(Color(hex: "#8A8A8A"))
            }
            .padding(.trailing, 7).background(Color.white).clipShape(Capsule()).offset(x: 15, y: -18)
        }
        .contentShape(Rectangle())
        .onTapGesture { openDetails(item) }
        .accessibilityIdentifier("result.hub.item.\(item.id.uuidString)")
    }

    private func expertCard(_ item: AnalysisResultHubItem, position: Int) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    HStack(spacing: 5) { Image(systemName: "photo"); Text("\(max(1, item.sourcePhotoIndices?.count ?? 1))") }
                        .font(referenceFont(10.5, .black)).foregroundStyle(Color(hex: "#3D3D3D"))
                        .padding(.horizontal, 7).padding(.vertical, 4).background(Color(hex: "#F2F4F1"))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: "#E6E9E4"), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text("\(copy("BULGU", "FINDING")) #\(item.ordinal ?? position)")
                        .font(referenceFont(10, .heavy)).tracking(0.4).foregroundStyle(muted)
                    Spacer()
                    if activeSection.access == .full { selectionControl(item) }
                }
                Text(item.displayTitle(language: language))
                    .font(referenceFont(14, .black)).foregroundStyle(ink).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.displayBody)
                    .font(referenceFont(12, .regular)).foregroundStyle(Color(hex: "#666666"))
                    .lineSpacing(3).padding(.top, 6).lineLimit(activeSection.access == .teaser ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if activeSection.access == .full { expertMeasures(item).padding(.top, 13) }
                else { lockedContent(item).padding(.top, 12) }
            }
            .padding(.horizontal, 13).padding(.top, 26).padding(.bottom, 14)
            if activeSection.access == .full { actionStrip(item) }
        }
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(green, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.10), radius: 7, x: 4, y: 6)
        .overlay(alignment: .topLeading) {
            Image(systemName: "lightbulb")
                .font(.system(size: 23, weight: .regular)).foregroundStyle(Color(hex: "#C9A227"))
                .frame(width: 36, height: 36).background(Color.white).clipShape(Circle()).offset(x: 15, y: -18)
        }
        .accessibilityIdentifier("result.hub.item.\(item.id.uuidString)")
    }

    private func expertMeasures(_ item: AnalysisResultHubItem) -> some View {
        let corrective = item.recommendedMeasures?.first(where: { $0.kind == .corrective })?.text ?? item.recommendedAction
        let preventive = item.recommendedMeasures?.first(where: { $0.kind == .preventive })?.text
        return VStack(alignment: .leading, spacing: 7) {
            Text(copy("ÖNLEM / KONTROL TEDBİRLERİ", "CONTROL MEASURES"))
                .font(referenceFont(9.5, .heavy)).tracking(0.6).foregroundStyle(Color(hex: "#8A8A8A"))
            if let corrective, !corrective.isEmpty { measureBlock(copy("DÜZELTİCİ ÖNLEM", "CORRECTIVE ACTION"), text: corrective) }
            if let preventive, !preventive.isEmpty { measureBlock(copy("ÖNLEYİCİ KONTROL", "PREVENTIVE CONTROL"), text: preventive) }
        }
    }

    private func measureBlock(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(referenceFont(9, .heavy)).tracking(0.5).foregroundStyle(greenDark)
            Text(text).font(referenceFont(11.5, .regular)).foregroundStyle(Color(hex: "#455047"))
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#F1FAEA"))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#DCEFCD"), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func featureTags(_ item: AnalysisResultHubItem) -> some View {
        let tags: [(String, Color)] = [
            (copy("Kök Neden", "Root Cause"), Color(hex: "#F8E07A")),
            (copy("Düzeltici Önlem", "Corrective Action"), Color(hex: "#C8ECB0")),
            (copy("Önleyici Faaliyet", "Preventive Action"), Color(hex: "#C8ECB0")),
            (copy("Mevzuat", "Regulation"), Color(hex: "#BCD8F5"))
        ]
        return WrappingHStack(spacing: 8) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                if featureAvailable(item, index: index) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(Color(hex: "#3F8A56"))
                        Text(tag.0).font(referenceFont(10.5, .heavy)).foregroundStyle(Color(hex: "#33403A"))
                    }
                    .padding(.horizontal, 3).padding(.vertical, 2).background(tag.1.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            Button { openDetails(item) } label: {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .black)).foregroundStyle(greenMuted)
                    .frame(width: 20, height: 20).background(Color(hex: "#EEF4EE")).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func featureAvailable(_ item: AnalysisResultHubItem, index: Int) -> Bool {
        switch index {
        case 0: return !(item.rootCauseText ?? "").isEmpty
        case 1: return !(item.recommendedAction ?? "").isEmpty || item.recommendedMeasures?.contains(where: { $0.kind == .corrective }) == true
        case 2: return item.recommendedMeasures?.contains(where: { $0.kind == .preventive }) == true
        default: return !(item.referencesText ?? "").isEmpty
        }
    }

    // MARK: Notebook

    private var notebookPaper: some View {
        VStack(spacing: 0) {
            HStack {
                Text(copy("ONAYLI DEFTER KAYITLARI", "SAFETY LOG ENTRIES"))
                    .font(referenceFont(9.5, .heavy)).tracking(0.7).foregroundStyle(Color(hex: "#A2937A"))
                Spacer()
                if activeSection.access == .teaser { Image(systemName: "lock.fill").foregroundStyle(Color(hex: "#A2937A")) }
            }
            .padding(.leading, 50).padding(.trailing, 15).padding(.vertical, 15)
            .background(Color(hex: "#FDFBF4"))
            VStack(spacing: 27) {
                ForEach(Array(activeSection.items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1)-").font(referenceFont(13, .heavy)).foregroundStyle(Color(hex: "#B3453C"))
                            .frame(width: 17, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notebookCombinedText(item))
                                .font(referenceFont(12.5, .medium)).foregroundStyle(Color(hex: "#2F3A44"))
                                .lineSpacing(11).lineLimit(activeSection.access == .teaser ? 2 : nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if activeSection.access == .teaser, let first = activeSection.items.first { lockedContent(first) }
            }
            .padding(.leading, 50).padding(.trailing, 15).padding(.vertical, 12)
            .background(NotebookRuledBackground(paper: Color(hex: "#FDFBF4"), line: Color(hex: "#DBE6F0")))
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy("UZMAN DEĞERLENDİRMESİ", "EXPERT REVIEW"))
                        .font(referenceFont(9.5, .heavy)).tracking(0.5).foregroundStyle(Color(hex: "#A2937A"))
                    Text(copy("Bu kayıt bir taslaktır", "This entry is a draft"))
                        .font(referenceFont(12, .bold)).foregroundStyle(Color(hex: "#3D4650"))
                }
                Spacer()
                VStack(spacing: 1) {
                    Text(copy("TASLAK", "DRAFT")).font(referenceFont(8.5, .heavy)).tracking(0.5)
                    Text(copy("UZMAN ONAYI", "EXPERT REVIEW")).font(referenceFont(8, .bold))
                }
                .foregroundStyle(Color(hex: "#B3453C")).frame(width: 74, height: 74)
                .overlay(Circle().stroke(Color(hex: "#C1A9A4"), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .rotationEffect(.degrees(-8))
            }
            .padding(.leading, 50).padding(.trailing, 15).padding(.vertical, 12)
            .background(Color(hex: "#FDFBF4"))
        }
        .overlay(alignment: .leading) {
            LinearGradient(colors: [Color(hex: "#C9B98C"), Color(hex: "#E3D7AE"), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 7)
            Rectangle().fill(Color(hex: "#DDA9A2")).frame(width: 1.5).offset(x: 38)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#E6DFC9"), lineWidth: 1))
        .clipShape(NotebookOuterShape())
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 5, y: 8)
    }

    private func notebookCombinedText(_ item: AnalysisResultHubItem) -> String {
        let finding = item.findingText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let recommendation = item.recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if activeSection.access == .teaser { return finding }
        var result = "\(copy("Tespit:", "Finding:")) \(finding) \(copy("Öneri:", "Recommendation:")) \(recommendation)"
        let basis = (item.referenceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !basis.isEmpty { result += " \(copy("Dayanak:", "Basis:")) \(basis)" }
        return result
    }

    // MARK: Shared item actions

    private func selectionControl(_ item: AnalysisResultHubItem, compact: Bool = false) -> some View {
        let selected = selectedIDs.contains(item.id)
        return Button {
            var next = selections[selectedSection] ?? []
            if selected { next.remove(item.id) } else { next.insert(item.id) }
            selections[selectedSection] = next
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 6) {
                if !compact {
                    Text(selected ? copy("Seçildi", "Selected") : copy("Seç", "Select"))
                        .font(referenceFont(11.5, .heavy)).foregroundStyle(selected ? greenDark : Color(hex: "#9A9A9A"))
                }
                Image(systemName: selected ? "checkmark" : "")
                    .font(.system(size: 10, weight: .black)).foregroundStyle(Color.white)
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .background(selected ? green : Color.white)
                    .overlay(Circle().stroke(selected ? green : Color(hex: "#CFCFCF"), lineWidth: 1.5))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? copy("Rapordan çıkar", "Remove from report") : copy("Rapora ekle", "Add to report"))
    }

    private func actionStrip(_ item: AnalysisResultHubItem) -> some View {
        HStack(spacing: 2) {
            if activeSection.canEdit {
                stripButton("pencil", label: copy("Düzenle", "Edit")) { edit(item) }
                stripButton("trash", label: copy("Sil", "Delete")) { delete(item) }
            }
            stripButton(reaction(for: item) == .like ? "hand.thumbsup.fill" : "hand.thumbsup", label: copy("Beğen", "Like")) {
                toggleReaction(item, reaction: .like)
            }
            stripButton(reaction(for: item) == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", label: copy("Beğenme", "Dislike")) {
                if reaction(for: item) == .dislike { toggleReaction(item, reaction: .dislike) }
                else { pendingDislike = item }
            }
            Spacer(minLength: 0)
            Button { openDetails(item) } label: {
                HStack(spacing: 5) { Text(copy("Ayrıntıları Gör", "View Details")); Image(systemName: "chevron.right") }
                    .font(referenceFont(11.5, .heavy)).foregroundStyle(.white).padding(.horizontal, 4).frame(height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("result.hub.item.details.\(item.id.uuidString)")
        }
        .padding(.horizontal, 10).frame(height: 48).background(green)
    }

    private func stripButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .regular)).foregroundStyle(.white).frame(width: 34, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func lockedContent(_ item: AnalysisResultHubItem) -> some View {
        VStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#D9DDD8")).frame(height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#E1E4E0")).frame(width: 210, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#E6E8E5")).frame(width: 160, height: 11)
            }
            .blur(radius: 3.5).accessibilityHidden(true)
            Button {
                Task {
                    await AnalysisResultHubService.shared.recordEvent(
                        analysisID: analysisID,
                        language: language,
                        name: "locked_teaser_cta_tapped",
                        section: selectedSection,
                        itemID: item.id,
                        funnelSessionID: funnelSessionID
                    )
                }
                onPaywall(selectedSection, funnelSessionID)
            } label: {
                HStack(spacing: 7) { Image(systemName: "lock.open.fill"); Text(copy("Plus / Pro ile tamamını aç", "Unlock all with Plus / Pro")) }
                    .font(referenceFont(12, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10).background(greenDark)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Bottom report CTA

    private var reportBar: some View {
        VStack(spacing: 6) {
            Button {
                if activeSection.access == .teaser || !activeSection.canReport {
                    onPaywall(selectedSection, funnelSessionID)
                } else if !selectedIDs.isEmpty {
                    reportKind = selectedSection == .riskAnalysis ? nil : .section
                    reportFormat = "pdf"
                    reportSheetDetent = ReferenceReportSheetLayout.compactDetent
                    reportSheetPresented = true
                }
            } label: {
                HStack(spacing: 0) {
                    HStack(spacing: 9) {
                        Image(systemName: activeSection.access == .teaser ? "lock.fill" : "slider.horizontal.3")
                            .font(.system(size: 18, weight: .regular))
                        Text(activeSection.access == .teaser ? copy("Plus / Pro ile Aç", "Unlock with Plus / Pro") : copy("Rapor Oluştur", "Create Report"))
                            .font(referenceFont(15.5, .heavy))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17, weight: .regular)).foregroundStyle(Color(hex: "#111111"))
                        .frame(width: 38, height: 38).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .padding(.trailing, 6).frame(height: 50)
                .background(selectedIDs.isEmpty && activeSection.access == .full ? Color(hex: "#6D6D6D") : Color(hex: "#111111"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.28), radius: 8, x: 4, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty && activeSection.access == .full)
            .accessibilityLabel(activeSection.access == .teaser
                                ? copy("Plus / Pro ile Aç", "Unlock with Plus / Pro")
                                : selectedSection == .approvedNotebook
                                    ? copy("Rapor Oluştur", "Create Report")
                                    : "\(copy("Rapor Oluştur", "Create Report")) · \(selectedIDs.count)/\(activeSection.count)")
            .accessibilityIdentifier("result.hub.report")
            if selectedSection != .approvedNotebook {
                Text(selectedCountText).font(referenceFont(10.5, .bold)).foregroundStyle(Color(hex: "#8A8A8A"))
            }
        }
        .padding(.horizontal, 20).padding(.top, 9).padding(.bottom, 18)
        .background(Color.white.shadow(.drop(color: Color.black.opacity(0.07), radius: 9, y: -6)))
    }

    // MARK: State and actions

    private var riskCounts: [RiskLevel: Int] { Dictionary(grouping: activeSection.items, by: riskLevel(for:)).mapValues(\.count) }
    private func riskLevel(for item: AnalysisResultHubItem) -> RiskLevel {
        let raw = method == .fineKinney ? item.fkBand : item.m5Band
        return RiskLevel(rawValue: raw ?? "unknown") ?? .unknown
    }
    private func riskRank(_ level: RiskLevel) -> Int {
        switch level { case .critical: 4; case .high: 3; case .medium: 2; case .low: 1; case .unknown: 0 }
    }
    private func referenceRiskColor(_ level: RiskLevel) -> Color {
        switch level {
        case .critical: Color(hex: "#C9352B")
        case .high: Color(hex: "#DD6B20")
        case .medium: Color(hex: "#C9A227")
        case .low: green
        case .unknown: Color(hex: "#8A8A8A")
        }
    }
    private func riskBandLabel(_ level: RiskLevel) -> String {
        switch level {
        case .critical: copy("KRİTİK RİSK", "CRITICAL RISK")
        case .high: copy("YÜKSEK RİSK", "HIGH RISK")
        case .medium: copy("ORTA RİSK", "MEDIUM RISK")
        case .low: copy("DÜŞÜK RİSK", "LOW RISK")
        case .unknown: copy("DEĞERLENDİRİLMEDİ", "UNASSESSED")
        }
    }
    private func methodRiskBandLabel(for item: AnalysisResultHubItem, fallback level: RiskLevel) -> String {
        let label: String?
        switch method {
        case .fineKinney:
            label = item.fkScore.map { RiskBands.fineKinney($0).label }
        case .matrix5x5:
            label = item.m5Score.map { RiskBands.matrix5x5($0).label }
        }
        let resolved = label ?? riskBandLabel(level)
        let locale = Locale(identifier: language == .turkish ? "tr_TR" : "en_US")
        return resolved.uppercased(with: locale)
    }
    private func shortRiskLabel(_ level: RiskLevel) -> String {
        switch level {
        case .critical: copy("KRT", "CRT")
        case .high: copy("YSK", "HGH")
        case .medium: copy("ORT", "MED")
        case .low: copy("DŞK", "LOW")
        case .unknown: "?"
        }
    }
    private func scoreText(_ score: Double) -> String {
        score.rounded() == score ? String(Int(score)) : String(format: "%.1f", score)
    }
    private func reaction(for item: AnalysisResultHubItem) -> AnalysisItemReaction {
        reactions[item.id] ?? item.userReaction ?? AnalysisItemReaction.none
    }
    private func openDetails(_ item: AnalysisResultHubItem) {
        if selectedSection == .riskAnalysis { onOpenFinding(item.asFindingRow(fallbackAnalysisID: analysisID)) }
        else { detailItem = item }
        Task {
            await AnalysisResultHubService.shared.recordEvent(
                analysisID: analysisID,
                language: language,
                name: "result_item_detail_opened",
                section: selectedSection,
                itemID: item.id,
                funnelSessionID: funnelSessionID
            )
        }
    }
    private func edit(_ item: AnalysisResultHubItem) {
        if selectedSection == .approvedNotebook {
            notebookFindingDraft = item.findingText ?? ""
            notebookRecommendationDraft = item.recommendationText ?? ""
            editingNotebook = item
        } else { onEditFinding(item.asFindingRow(fallbackAnalysisID: analysisID)) }
    }
    private func delete(_ item: AnalysisResultHubItem) {
        if selectedSection == .approvedNotebook { pendingNotebookSuppression = item }
        else { onDeleteFinding(item.asFindingRow(fallbackAnalysisID: analysisID)) }
    }
    private func toggleReaction(_ item: AnalysisResultHubItem, reaction: AnalysisItemReaction) {
        let next: AnalysisItemReaction = self.reaction(for: item) == reaction ? .none : reaction
        reactions[item.id] = next
        Task {
            try? await AnalysisResultHubService.shared.setFeedback(
                analysisID: analysisID, language: language, section: selectedSection, item: item, reaction: next
            )
        }
    }
    private func dislikeReasonButton(_ label: String, code: String) -> some View { Button(label) { submitPendingDislike(reason: code) } }
    private func submitPendingDislike(reason: String?) {
        guard let item = pendingDislike else { return }
        pendingDislike = nil
        reactions[item.id] = .dislike
        Task {
            try? await AnalysisResultHubService.shared.setFeedback(
                analysisID: analysisID, language: language, section: selectedSection, item: item, reaction: .dislike, reason: reason
            )
        }
    }
    private func initializeState() {
        for section in hub.sections {
            if selections[section.id] == nil { selections[section.id] = section.access == .full ? Set(section.items.map(\.id)) : [] }
            for item in section.items { reactions[item.id] = item.userReaction ?? AnalysisItemReaction.none }
        }
    }

    private func notebookEditor(_ item: AnalysisResultHubItem) -> some View {
        NavigationStack {
            Form {
                Section(copy("Tespit", "Finding")) { TextEditor(text: $notebookFindingDraft).frame(minHeight: 120) }
                Section(copy("Öneri", "Recommendation")) { TextEditor(text: $notebookRecommendationDraft).frame(minHeight: 150) }
                Section {
                    Text(copy("Bu içerik Onaylı Defter taslağıdır; uzman değerlendirmesi gerekir.", "This is a Safety Log draft and requires expert review."))
                        .font(.footnote).foregroundStyle(Color.rdSlate)
                }
            }
            .navigationTitle(copy("Defter Taslağını Düzenle", "Edit Safety Log Draft"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(copy("Vazgeç", "Cancel")) { editingNotebook = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("Kaydet", "Save")) {
                        onEditNotebook(item, notebookFindingDraft, notebookRecommendationDraft)
                        editingNotebook = nil
                    }
                    .disabled(notebookFindingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || notebookRecommendationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var premiumPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").foregroundStyle(Color(hex: "#E0A828")); Text("PLUS").foregroundStyle(Color(hex: "#A67C12"))
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 1, height: 9)
            Image(systemName: "star.fill").foregroundStyle(green); Text("PRO").foregroundStyle(greenDark)
        }
        .font(referenceFont(9, .black)).padding(.horizontal, 8).padding(.vertical, 3).background(Color.white)
        .clipShape(Capsule()).padding(1.5)
        .background(LinearGradient(colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")], startPoint: .leading, endPoint: .trailing))
        .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 26, weight: .medium)).foregroundStyle(greenDark)
            Text(copy("Bu bölümde kayıt bulunmuyor", "No entries in this section")).font(referenceFont(14, .heavy))
            Text(copy("Analiz sonuçları uygun olduğunda burada listelenecek.", "Eligible analysis results will appear here."))
                .font(referenceFont(12, .regular)).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
    }
    private func copy(_ turkish: String, _ english: String) -> String { language == .turkish ? turkish : english }
    private func referenceFont(_ size: CGFloat, _ weight: Font.Weight) -> Font { ResultTypography.font(size, weight) }
}

// MARK: Report sheet

private enum ReferenceReportSheetLayout {
    // Both detents remain registered for the lifetime of the risk sheet. Updating
    // only the selected detent avoids UIKit falling back to the large detent when
    // the risk-table controls are inserted into the hierarchy.
    static let compactHeight: CGFloat = 360
    static let expandedHeight: CGFloat = 510
    static let compactDetent: PresentationDetent = .height(compactHeight)
    static let expandedDetent: PresentationDetent = .height(expandedHeight)
}

private enum ReferenceReportKind: String, Identifiable { case standard, riskTable, section; var id: String { rawValue } }

private struct ReferenceReportSheet: View {
    let section: AnalysisResultSectionID
    let language: RDLanguage
    let selectedCount: Int
    let totalCount: Int
    let isFreeTier: Bool
    let canReport: Bool
    @Binding var method: RiskMethod
    @Binding var reportKind: ReferenceReportKind?
    @Binding var reportFormat: String
    @Binding var selectedDetent: PresentationDetent
    let onClose: () -> Void
    let onUpgrade: () -> Void
    let onGenerate: () -> Void

    private let green = Color(hex: "#35774A")
    private let greenDark = Color(hex: "#2E6B41")
    private var isRisk: Bool { section == .riskAnalysis }
    private var canGenerate: Bool {
        guard canReport, selectedCount > 0 else { return false }
        return !isRisk || reportKind != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: "#DCDCDC")).frame(width: 42, height: 5).padding(.top, 10)
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40)
                    .background(LinearGradient(colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color(hex: "#1F8F9C").opacity(0.26), radius: 6, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        Text(copy("Raporunu oluştur ve ", "Create and "))
                            .foregroundStyle(Color(hex: "#1A1A1A"))
                        Text(copy("paylaş", "share your report"))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#E8762A"), Color(hex: "#1F8F9C")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .font(ResultTypography.font(15, .black))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(copy("Raporunu oluştur ve paylaş", "Create and share your report"))
                    Text("\(selectedCount)/\(totalCount) \(copy("kayıt seçili", "items selected")) · PDF \(copy("veya", "or")) Excel")
                        .font(ResultTypography.font(10, .semibold)).foregroundStyle(Color(hex: "#A0A0A0"))
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "#6D6D6D"))
                        .frame(width: 36, height: 36).background(Color(hex: "#F2F2F2")).clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 11)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if isRisk {
                        reportTypeCard(
                            kind: .standard,
                            title: copy("Standart Rapor", "Standard Report"),
                            subtitle: copy("Seçili bulguların özet dökümü", "Summary of selected findings"),
                            icon: "doc.text"
                        )
                        reportTypeCard(
                            kind: .riskTable,
                            title: copy("Risk Analizi Tablosu", "Risk Analysis Table"),
                            subtitle: copy(
                                "Analizlerini Fine-Kinney veya 5x5 Matris ile hesapla, PDF ya da Excel olarak rapor oluştur ve paylaş.",
                                "Calculate with Fine-Kinney or 5x5 Matrix, then create and share a PDF or Excel report."
                            ),
                            icon: "tablecells",
                            emphasized: true
                        )
                        if reportKind == .riskTable {
                            fieldTitle(copy("YÖNTEM", "METHOD")); segmentedMethod
                            fieldTitle(copy("ÇIKTI BİÇİMİ", "OUTPUT FORMAT")); segmentedFormat
                        }
                        if isFreeTier && !canReport { upgradeCard }
                    } else {
                        fieldTitle(copy("ÇIKTI BİÇİMİ SEÇİN", "SELECT OUTPUT FORMAT"))
                        formatCard("pdf", title: copy("PDF olarak indir", "Download as PDF"), subtitle: copy("Baskıya ve paylaşıma hazır düzen", "Print-ready and shareable layout"))
                        formatCard("xlsx", title: copy("Excel olarak indir", "Download as Excel"), subtitle: copy("Düzenlenebilir tablo, filtreli sütunlar", "Editable table with filtered columns"))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 14)
            }
            Button {
                if canGenerate { onGenerate() } else if !canReport { onUpgrade() }
            } label: {
                HStack(spacing: 9) { Image(systemName: canReport ? "arrow.down.to.line" : "lock.fill"); Text(generateTitle) }
                    .font(ResultTypography.font(14, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canGenerate ? Color(hex: "#111111") : (canReport ? Color(hex: "#D8D8D8") : greenDark))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: canGenerate ? Color.black.opacity(0.28) : .clear, radius: 8, x: 4, y: 7)
            }
            .buttonStyle(.plain).disabled(!canGenerate && canReport)
            .accessibilityIdentifier("result.report_sheet.generate")
            .padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 14)
            .background(Color.white.shadow(.drop(color: Color.black.opacity(0.06), radius: 9, y: -6)))
        }
        .background(Color.white)
        .accessibilityIdentifier("result.report_sheet")
    }

    private func reportTypeCard(
        kind: ReferenceReportKind,
        title: String,
        subtitle: String,
        icon: String,
        emphasized: Bool = false
    ) -> some View {
        let selected = reportKind == kind
        return Button {
            if kind == .riskTable && !canReport {
                onUpgrade()
            } else {
                reportKind = kind
                if isRisk {
                    selectedDetent = kind == .riskTable
                        ? ReferenceReportSheetLayout.expandedDetent
                        : ReferenceReportSheetLayout.compactDetent
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                reportTypeIcon(icon, selected: selected, emphasized: emphasized)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(ResultTypography.font(12.5, .heavy)).foregroundStyle(Color(hex: "#1A1A1A"))
                    reportTypeSubtitle(subtitle, emphasized: emphasized)
                        .font(ResultTypography.font(10, .medium))
                        .foregroundStyle(Color(hex: "#9A9A9A"))
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(); radio(selected)
            }
            .padding(.horizontal, 13).padding(.vertical, emphasized ? 13 : 10)
            .frame(minHeight: emphasized ? 94 : 60, alignment: .top)
            .background(selected ? Color(hex: "#F6FBF1") : .white)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(selected ? green : Color(hex: "#ECECEC"), lineWidth: selected ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("result.report_sheet.option.\(kind.rawValue)")
    }

    @ViewBuilder
    private func reportTypeSubtitle(_ fallback: String, emphasized: Bool) -> some View {
        if emphasized {
            riskTableSubtitle
        } else {
            Text(fallback)
        }
    }

    private var riskTableSubtitle: Text {
        if language == .turkish {
            return Text("Analizlerini ")
                + Text("Fine-Kinney").underline()
                + Text(" veya ")
                + Text("5x5 Matris").underline()
                + Text(" ile hesapla, ")
                + Text("PDF").underline()
                + Text(" ya da ")
                + Text("Excel").underline()
                + Text(" olarak rapor oluştur ve paylaş.")
        }
        return Text("Calculate with ")
            + Text("Fine-Kinney").underline()
            + Text(" or ")
            + Text("5x5 Matrix").underline()
            + Text(", then create and share a ")
            + Text("PDF").underline()
            + Text(" or ")
            + Text("Excel").underline()
            + Text(" report.")
    }

    @ViewBuilder
    private func reportTypeIcon(_ icon: String, selected: Bool, emphasized: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        if emphasized {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: selected
                            ? [green, greenDark]
                            : [Color(hex: "#E9A62C"), Color(hex: "#2C9B82")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(shape)
        } else {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(selected ? .white : Color(hex: "#929292"))
                .frame(width: 40, height: 40)
                .background(selected ? green : Color(hex: "#F4F4F4"))
                .clipShape(shape)
        }
    }

    private func formatCard(_ format: String, title: String, subtitle: String) -> some View {
        let selected = reportFormat == format
        let pdf = format == "pdf"
        return Button { reportFormat = format } label: {
            HStack(spacing: 10) {
                Text(pdf ? "PDF" : "XLS").font(ResultTypography.font(9, .black))
                    .foregroundStyle(pdf ? Color(hex: "#C9352B") : greenDark).frame(width: 32, height: 32)
                    .background(pdf ? Color(hex: "#FDECEA") : Color(hex: "#EAF6EE")).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ResultTypography.font(12.5, .heavy)).foregroundStyle(selected ? greenDark : Color(hex: "#1A1A1A"))
                    Text(subtitle).font(ResultTypography.font(10, .medium)).foregroundStyle(Color(hex: "#9A9A9A"))
                }
                Spacer(); radio(selected)
            }
            .padding(11).background(selected ? Color(hex: "#F6FBF1") : .white)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? green : Color(hex: "#ECECEC"), lineWidth: selected ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var segmentedMethod: some View {
        HStack(spacing: 3) {
            segment("Fine-Kinney", subtitle: "O × F × Ş", selected: method == .fineKinney) { method = .fineKinney }
            segment(copy("5x5 Matris", "5x5 Matrix"), subtitle: "O × Ş", selected: method == .matrix5x5) { method = .matrix5x5 }
        }
        .padding(4).background(Color(hex: "#F4F4F4")).clipShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityIdentifier("result.report_sheet.method")
    }

    private var segmentedFormat: some View {
        HStack(spacing: 3) {
            segment("PDF", subtitle: copy("Baskıya hazır", "Print ready"), selected: reportFormat == "pdf") { reportFormat = "pdf" }
            segment("Excel", subtitle: copy("Düzenlenebilir", "Editable"), selected: reportFormat == "xlsx") { reportFormat = "xlsx" }
        }
        .padding(4).background(Color(hex: "#F4F4F4")).clipShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityIdentifier("result.report_sheet.format")
    }

    private func segment(_ title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                }
                VStack(spacing: 2) {
                    Text(title).font(ResultTypography.font(11.5, .heavy))
                    Text(subtitle).font(ResultTypography.font(9, .semibold))
                }
                .foregroundStyle(selected ? greenDark : Color(hex: "#8A8A8A"))
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var upgradeCard: some View {
        Button(action: onUpgrade) {
            HStack(spacing: 9) {
                Image(systemName: "lock.fill").foregroundStyle(Color(hex: "#A99A6D")).frame(width: 30, height: 30)
                    .background(Color(hex: "#F1EFE7")).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy("PLUS veya PRO ile aç", "Unlock with PLUS or PRO")).font(ResultTypography.font(12.5, .heavy))
                    Text(copy("Rapor hakları ve Excel çıktısı", "Report access and Excel export"))
                        .font(ResultTypography.font(10, .semibold)).foregroundStyle(Color(hex: "#A8A8A8"))
                }
                Spacer()
                Text("PLUS / PRO").font(ResultTypography.font(8, .black)).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.white).clipShape(Capsule())
            }
            .foregroundStyle(Color(hex: "#8A8A8A")).padding(10).background(Color(hex: "#FBFBFA"))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(hex: "#DDD7C6"), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func radio(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark" : "").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
            .frame(width: 22, height: 22).background(selected ? green : Color.white)
            .overlay(Circle().stroke(selected ? green : Color(hex: "#D6D6D6"), lineWidth: 1.5)).clipShape(Circle())
    }
    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(ResultTypography.font(9, .heavy)).tracking(0.6).foregroundStyle(Color(hex: "#B2B2B2"))
    }
    private var generateTitle: String {
        if !canReport { return copy("PLUS / PRO ile aç", "Unlock with PLUS / PRO") }
        guard canGenerate else { return copy("Rapor türü seçin", "Select report type") }
        if reportKind == .standard { return copy("Standart Rapor Oluştur", "Create Standard Report") }
        return reportFormat == "xlsx" ? copy("Excel Raporu Oluştur", "Create Excel Report") : copy("PDF Raporu Oluştur", "Create PDF Report")
    }
    private func copy(_ tr: String, _ en: String) -> String { language == .turkish ? tr : en }
}

// MARK: Expert / notebook detail sheet

private struct ReferenceHubDetailView: View {
    let item: AnalysisResultHubItem
    let section: AnalysisResultSectionID
    let language: RDLanguage
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let green = Color(hex: "#35774A")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 17, weight: .semibold)).frame(width: 36, height: 36)
                        .background(Color(hex: "#F2F2F2")).clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(section.title(language: language)).font(ResultTypography.font(15, .heavy))
                Spacer()
                Menu {
                    Button(action: onEdit) { Label(copy("Düzenle", "Edit"), systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) { Label(copy("Sil", "Delete"), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 36, height: 36)
                        .background(Color(hex: "#F2F2F2")).clipShape(Circle())
                }
            }
            .foregroundStyle(Color(hex: "#1A1A1A")).padding(.horizontal, 18).padding(.vertical, 10)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.displayTitle(language: language)).font(ResultTypography.font(22, .black)).foregroundStyle(Color(hex: "#1A1A1A"))
                    if !item.displayBody.isEmpty { detailBlock(copy("Açıklama", "Description"), item.displayBody, color: Color(hex: "#EEF3FA")) }
                    if let root = item.rootCauseText, !root.isEmpty { detailBlock(copy("Kök Neden", "Root Cause"), root, color: Color(hex: "#FFF8E3")) }
                    if let action = item.recommendedAction, !action.isEmpty { detailBlock(copy("Öneri", "Recommendation"), action, color: Color(hex: "#F1FAEA")) }
                    if let finding = item.findingText, !finding.isEmpty { detailBlock(copy("Tespit", "Finding"), finding, color: Color(hex: "#FFF8E3")) }
                    if let recommendation = item.recommendationText, !recommendation.isEmpty { detailBlock(copy("Öneri", "Recommendation"), recommendation, color: Color(hex: "#F1FAEA")) }
                    if let reference = item.referenceText ?? item.referencesText, !reference.isEmpty { detailBlock(copy("Dayanak", "Basis"), reference, color: Color(hex: "#EEF3FA")) }
                }
                .padding(20)
            }
        }
        .background(Color.white)
    }
    private func detailBlock(_ title: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(ResultTypography.font(10.5, .black)).tracking(0.6).foregroundStyle(green)
            Text(text).font(ResultTypography.font(13.5, .regular)).foregroundStyle(Color(hex: "#3D4650"))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading).background(color).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func copy(_ tr: String, _ en: String) -> String { language == .turkish ? tr : en }
}

// MARK: Reference geometry

private struct ConnectedTabFill: Shape {
    let cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.closeSubpath(); return path
    }
}
private struct ConnectedTabBorder: Shape {
    let cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); return path
    }
}
private struct NotebookRuledBackground: View {
    let paper: Color
    let line: Color
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                paper
                Canvas { context, size in
                    var y: CGFloat = 26
                    while y < size.height {
                        var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(line), lineWidth: 1); y += 27
                    }
                }
            }
        }
    }
}
private struct NotebookOuterShape: Shape { func path(in rect: CGRect) -> Path { RoundedRectangle(cornerRadius: 10).path(in: rect) } }

private struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content
    init(spacing: CGFloat, @ViewBuilder content: () -> Content) { self.spacing = spacing; self.content = content() }
    var body: some View { ReferenceFlowLayout(spacing: spacing) { content } }
}

private struct ReferenceFlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}
