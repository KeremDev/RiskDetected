import SwiftUI
import UIKit

struct AnalysisResultPaywallRequest {
    let section: AnalysisResultSectionID
    let funnelSessionID: UUID
    let itemID: String?
    let attributes: [String: String]
}

enum AnalysisResultHubReportKind: String, Identifiable {
    case standard
    case riskTable
    case section

    var id: String { rawValue }

    var pdfReportKind: PDFReportKind? {
        switch self {
        case .standard:
            return .standard
        case .riskTable:
            return .riskAnalysis
        case .section:
            return nil
        }
    }
}

/// Native SwiftUI projection of the approved 440 × 956 result-hub reference.
/// Product data and permissions remain authoritative while the supplied HTML
/// defines layout, hierarchy and interaction styling.
struct AnalysisResultHubView: View {
    private enum ScrollAnchor: Hashable {
        case top
    }

    let hub: AnalysisResultHubResponse
    let analysisID: UUID
    let language: RDLanguage
    let analysisTitle: String
    let analysisSector: String?
    let analysisPhotos: [ResultPhotoItem]
    let freeRiskAnalysisTrialRemaining: Int
    @Binding var method: RiskMethod
    @Binding var selectedCompany: Company?
    let onBack: () -> Void
    let onOpenAnalysisPhoto: (UIImage) -> Void
    let onOpenFinding: (FindingRow, AnalysisResultSectionID) -> Void
    let onEditFinding: (FindingRow) -> Void
    let onDeleteFinding: (FindingRow) -> Void
    let onPaywall: (AnalysisResultPaywallRequest) -> Void
    let onCreateReport: (AnalysisResultSectionID, [UUID], String, AnalysisResultHubReportKind) -> Void
    let onEditNotebook: (AnalysisResultHubItem, String, String) -> Void
    let onSuppressNotebook: (AnalysisResultHubItem) -> Void

    @State private var selectedSection: AnalysisResultSectionID = .riskAnalysis
    @State private var selections: [AnalysisResultSectionID: Set<UUID>] = [:]
    @State private var reactions: [UUID: AnalysisItemReaction] = [:]
    @State private var detailItem: AnalysisResultHubItem?
    @State private var pendingDislike: AnalysisResultHubItem?
    @State private var feedbackComposerExpanded = false
    @State private var feedbackToastToken: UUID?
    @State private var editingNotebook: AnalysisResultHubItem?
    @State private var pendingNotebookSuppression: AnalysisResultHubItem?
    @State private var notebookFindingDraft = ""
    @State private var notebookRecommendationDraft = ""
    @State private var reportSheetPresented = false
    @State private var reportKind: AnalysisResultHubReportKind?
    @State private var reportFormat = "pdf"
    @State private var reportSheetHeight = ReferenceReportSheetLayout.initialHeight
    @State private var reportSheetDetent: PresentationDetent = .height(ReferenceReportSheetLayout.compactHeight)
    @State private var funnelSessionID = UUID()
    @State private var selectedTrainingGroup: String?

    private let green = Color.rdResultGreen
    private let greenDark = Color.rdResultGreenDark
    private let greenMuted = Color.rdResultGreenMuted
    private let ink = Color.rdResultPrimaryText
    private let muted = Color.rdResultSecondaryText

    /// The risk-analysis cards retain their established green controls. The
    /// three supporting sections each own one visual identity end to end.
    private var activeAccent: Color {
        switch selectedSection {
        case .riskAnalysis: return green
        case .expertRecommendations: return .rdSectionExpertAccent
        case .approvedNotebook: return .rdSectionNotebookAccent
        case .trainingRecommendations: return .rdSectionTrainingAccent
        }
    }

    private var activeStrong: Color {
        switch selectedSection {
        case .riskAnalysis: return greenDark
        case .expertRecommendations: return .rdSectionExpertStrong
        case .approvedNotebook: return .rdSectionNotebookStrong
        case .trainingRecommendations: return .rdSectionTrainingStrong
        }
    }

    private var activeTint: Color {
        switch selectedSection {
        case .riskAnalysis: return .rdResultGreenTint
        case .expertRecommendations: return .rdSectionExpertTint
        case .approvedNotebook: return .rdSectionNotebookTint
        case .trainingRecommendations: return .rdSectionTrainingTint
        }
    }

    private var summaryGradientColors: [Color] {
        switch selectedSection {
        case .riskAnalysis:
            return [Color(hex: "#3F6FA8"), Color(hex: "#2F5183"), Color(hex: "#1F3557")]
        case .expertRecommendations:
            return [.rdSectionExpertStart, .rdSectionExpertAccent, .rdSectionExpertEnd]
        case .approvedNotebook:
            return [.rdSectionNotebookStart, .rdSectionNotebookAccent, .rdSectionNotebookEnd]
        case .trainingRecommendations:
            return [.rdSectionTrainingStart, .rdSectionTrainingAccent, .rdSectionTrainingEnd]
        }
    }

    private var activeSection: AnalysisResultSection {
        hub.sections.first(where: { $0.id == selectedSection })
            ?? AnalysisResultSection(
                id: selectedSection,
                access: .full,
                count: 0,
                canEdit: false,
                canReport: false,
                items: [],
                observationBasis: nil
            )
    }

    private var selectedIDs: Set<UUID> { selections[selectedSection] ?? [] }
    private var reactionSignature: String {
        hub.sections.flatMap(\.items).map {
            "\($0.id.uuidString.lowercased()):\(($0.userReaction ?? .none).rawValue)"
        }.joined(separator: "|")
    }
    private var isFreeTier: Bool { (hub.tier ?? "").lowercased() == "free" }
    private var isPlusTier: Bool { (hub.tier ?? "").lowercased() == "plus" }
    private var membershipTier: SubscriptionTier {
        switch (hub.tier ?? "").lowercased() {
        case "pro": return .pro
        case "plus": return .plus
        default: return .free
        }
    }
    private var reportSheetDetents: Set<PresentationDetent> {
        if selectedSection != .riskAnalysis {
            return [ReferenceReportSheetLayout.nonRiskDetent]
        }

        // Keep the currently selected value registered while the measured height
        // changes. This prevents UIKit from jumping to an unrelated detent during
        // the same layout transaction. `.large` remains a user-expandable escape
        // hatch when future report fields exceed the available fitted height.
        return [.height(reportSheetHeight), reportSheetDetent, .large]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Color.clear
                            .frame(height: 0)
                            .id(ScrollAnchor.top)

                        Section {
                            sectionContent
                                .padding(.horizontal, 20)
                                .padding(.bottom, 28)
                        } header: {
                            sectionSelector
                        }
                    }
                }
                .onChange(of: selectedSection) { _ in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(ScrollAnchor.top, anchor: .top)
                    }
                }
            }
            .background(Color.rdResultBackground)
            reportBar
        }
        .background(Color.rdResultBackground.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .top) {
            if feedbackToastToken != nil {
                FeedbackThanksToast(language: language)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: feedbackToastToken)
        .overlay {
            if let item = pendingDislike {
                DislikeFeedbackPanel(
                    language: language,
                    isComposerExpanded: $feedbackComposerExpanded,
                    onClose: { pendingDislike = nil },
                    onSubmit: { reason, note in
                        await submitDislike(item: item, reason: reason, note: note)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(200)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.88), value: pendingDislike?.id)
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
        .onChange(of: reactionSignature) { _ in
            syncReactionsFromHub()
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
                accessTier: membershipTier,
                canReport: activeSection.canReport,
                freeRiskAnalysisTrialRemaining: freeRiskAnalysisTrialRemaining,
                method: $method,
                selectedCompany: $selectedCompany,
                reportKind: $reportKind,
                reportFormat: $reportFormat,
                preferredHeight: $reportSheetHeight,
                selectedDetent: $reportSheetDetent,
                onClose: { reportSheetPresented = false },
                onUpgrade: {
                    reportSheetPresented = false
                    requestPaywall(
                        section: selectedSection,
                        placement: "report_sheet_upgrade",
                        entryKind: "report_gate"
                    )
                },
                onGenerate: {
                    guard let reportKind else { return }
                    let format = reportKind == .standard ? "pdf" : reportFormat
                    reportSheetPresented = false
                    onCreateReport(selectedSection, Array(selectedIDs), format, reportKind)
                }
            )
            .presentationDetents(reportSheetDetents, selection: $reportSheetDetent)
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $editingNotebook) { item in notebookEditor(item) }
        .alert(copy("analysis.result_hub.v2.defter.kayd.gizlensin.mi.f11e0473", "Defter kaydı gizlensin mi?", "Hide this Safety Log entry?"), isPresented: Binding(
            get: { pendingNotebookSuppression != nil },
            set: { if !$0 { pendingNotebookSuppression = nil } }
        )) {
            Button(copy("analysis.result_hub.v2.vazgec.583c4eba", "Vazgeç", "Cancel"), role: .cancel) { pendingNotebookSuppression = nil }
            Button(copy("analysis.result_hub.v2.gizle.67e5db38", "Gizle", "Hide"), role: .destructive) {
                guard let item = pendingNotebookSuppression else { return }
                pendingNotebookSuppression = nil
                onSuppressNotebook(item)
            }
        } message: {
            Text(copy("analysis.result_hub.v2.kay.t.geri.al.nabilir.bicimde.gizlenecek.g.1e0e2256", "Kayıt geri alınabilir biçimde gizlenecek; geçmiş raporlar değişmeyecek.", "The entry will be hidden reversibly; previous report snapshots will not change."))
        }
    }

    // MARK: Connected section selector

    private var sectionSelector: some View {
        GeometryReader { proxy in
            let count = max(1, hub.sections.count)
            let gaps = CGFloat(max(0, count - 1)) * 6.7
            // Three tabs fill the width; a fourth has to announce itself. Sizing
            // for 3.5 leaves the last tab half on screen, which is what tells a
            // reader the strip scrolls -- a tab entirely past the edge is a tab
            // nobody finds. The gutter narrows to 14 to buy that half back.
            let visibleTabs: CGFloat = count <= 3 ? CGFloat(count) : 3.5
            let fitted = (proxy.size.width - 28 - gaps) / visibleTabs
            let tabWidth = max(88, fitted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6.7) {
                    ForEach(hub.sections) { section in
                        sectionTab(section, width: tabWidth)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minWidth: proxy.size.width, minHeight: 96, alignment: .bottomLeading)
            }
            // Keep the shared rail behind the tabs. The selected tab's white
            // bottom mask interrupts the rail and connects it to the content.
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(sectionAccentColor(selectedSection))
                    .frame(height: 1.5)
            }
        }
        .frame(height: 96)
        .background(Color.rdResultBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.hub.section_selector")
        .zIndex(20)
    }

    private func sectionTab(_ section: AnalysisResultSection, width: CGFloat) -> some View {
        let selected = selectedSection == section.id
        let tabSurface = selected ? Color.rdResultElevatedSurface : Color.rdResultSurface
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
                    .font(RDTypography.font(size: 20, weight: .regular))
                    .foregroundStyle(selected ? sectionAccentColor(section.id) : Color.rdResultPrimaryText)
                Text(section.id.compactTitle(language: language))
                    .font(referenceFont(11.5, .heavy))
                    .foregroundStyle(Color.rdResultPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("\(section.count) \(section.id.countLabel(language: language, count: section.count))")
                    .font(referenceFont(10, .semibold))
                    .foregroundStyle(Color.rdResultSecondaryText)
                    .lineLimit(1)
            }
            .frame(width: width, height: selected ? 84 : 72)
            .background(
                Group {
                    if selected {
                        ConnectedTabFill(cornerRadius: 8)
                            .fill(tabSurface)
                    }
                    else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tabSurface)
                    }
                }
            )
            .overlay {
                if selected {
                    ConnectedTabBorder(cornerRadius: 8)
                        .stroke(
                            sectionAccentColor(section.id),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle()
                        .fill(tabSurface)
                        .frame(height: 2.5)
                }
            }
            .padding(.bottom, selected ? 0 : 8)
        }
        .buttonStyle(.plain)
        .zIndex(selected ? 2 : 1)
        .accessibilityLabel("\(section.id.title(language: language)), \(section.count) \(section.id.countLabel(language: language, count: section.count))")
        .accessibilityIdentifier("result.hub.section.\(section.id.rawValue)")
    }

    private func sectionIcon(_ id: AnalysisResultSectionID) -> String {
        switch id {
        case .riskAnalysis: return "exclamationmark.triangle"
        case .expertRecommendations: return "person.badge.shield.checkmark"
        case .approvedNotebook: return "book.closed"
        case .trainingRecommendations: return "graduationcap"
        }
    }

    private func sectionAccentColor(_ id: AnalysisResultSectionID) -> Color {
        switch id {
        case .riskAnalysis: return .rdResultGreen
        case .expertRecommendations: return .rdSectionExpertAccent
        case .approvedNotebook: return .rdSectionNotebookAccent
        case .trainingRecommendations: return .rdSectionTrainingAccent
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
            case .trainingRecommendations: trainingContent
            }
        }
    }

    private var riskContent: some View {
        let premiumInsertionIndex = min(1, max(0, activeSection.items.count - 1))

        return VStack(spacing: 0) {
            analysisInfoCard.padding(.top, 12)
            riskSummary.padding(.top, 10)
            methodSelector.padding(.top, 9)
            selectionControls.padding(.top, 12).padding(.bottom, 20)
            LazyVStack(spacing: 34) {
                ForEach(Array(activeSection.items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 16) {
                        riskCard(item, position: index + 1)
                        if isFreeTier && index == premiumInsertionIndex {
                            premiumDeepAnalysisCard(
                                source: item,
                                position: premiumInsertionIndex + 2
                            )
                        }
                        if isPlusTier && index == premiumInsertionIndex {
                            proUpgradeCard(
                                section: .riskAnalysis,
                                afterItemCount: index + 1
                            )
                        }
                    }
                }
            }
        }
    }

    private var expertContent: some View {
        let proInsertionIndex = min(1, max(0, activeSection.items.count - 1))

        return VStack(spacing: 0) {
            nonRiskSummary.padding(.top, 12)
            selectionControls.padding(.top, 12).padding(.bottom, 26)
            LazyVStack(spacing: 34) {
                ForEach(Array(activeSection.items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 16) {
                        expertCard(item, position: index + 1)
                        if isPlusTier && index == proInsertionIndex {
                            proUpgradeCard(
                                section: .expertRecommendations,
                                afterItemCount: index + 1
                            )
                        }
                    }
                }
            }
        }
    }

    private var notebookContent: some View {
        VStack(spacing: 0) {
            nonRiskSummary.padding(.top, 12)
            if activeSection.access == .full, activeSection.observationBasis != nil {
                observationBasisNote.padding(.top, 14)
            }
            notebookPaper.padding(.top, 16)
        }
    }

    /// Kayıtların hangi dayanakla yazıldığını söyleyen tek satır.
    ///
    /// Seçim değil, beyan. Bu üründeki her fotoğrafı sahayı gezen uzmanın
    /// kendisi çekiyor; diğer dayanaklar kimsenin vermesi gerekmeyen bir karardı
    /// ve yalnızca yanlışlıkla yanlış şey söylemenin yolunu açıyordu. Yine de
    /// yazılı: cümleler uzmanın sahada olduğunu iddia ediyor, okuyucu bunu
    /// görmeli.
    private var observationBasisNote: some View {
        HStack(spacing: 7) {
            Image(systemName: "mappin.and.ellipse")
                .font(RDTypography.font(size: 11, weight: .semibold))
                .foregroundStyle(activeStrong)
            Text(copy("analysis.result_hub.v2.kay.tlar.saha.incelemesi.dayanag.yla.yaz.l.cc69a20f", "Kayıtlar saha incelemesi dayanağıyla yazılmıştır.", "Entries are written on the basis of a site inspection."))
            .font(referenceFont(11, .medium))
            .foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("result.hub.notebook.basis_note")
    }

    /// Eğitim önerileri.
    ///
    /// Analizde görülen tehlike mekanizmalarına ve ekipmana göre, ilgili
    /// çalışan gruplarına hangi eğitimlerin anlamlı olduğunu söyler. Onay,
    /// seçim veya form beklemez; analiz tamamlandığında hazırdır.
    private var trainingContent: some View {
        let groups = trainingGroups
        let active = activeTrainingGroup(in: groups)
        // `nil` is the deliberate "All" state. Keeping it as the default
        // means the screen never opens on an arbitrary first category and the
        // user sees the complete training plan immediately.
        let items = active.flatMap { code in
            groups.first(where: { $0.code == code })?.items
        } ?? activeSection.items
        let promotionInsertionIndex = min(1, max(0, items.count - 1))

        return VStack(spacing: 0) {
            nonRiskSummary.padding(.top, 12)
            if !groups.isEmpty {
                trainingGroupFilter(groups: groups, active: active)
                    .padding(.top, 14)
            }
            LazyVStack(spacing: 34) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 16) {
                        trainingCard(item)
                        if index == promotionInsertionIndex {
                            trainingMembershipPromotion(afterItemCount: index + 1)
                        }
                    }
                }
            }
            .padding(.top, 26)
        }
    }

    private struct TrainingGroup {
        let code: String
        let label: String
        let icon: String
        let items: [AnalysisResultHubItem]
    }

    /// Gruplar, kart taşıyanlar sırasıyla.
    ///
    /// Sıra bilgi taşıyor: sahada görülene dayanan öneriler önce, her işyeri
    /// için doğru olan temel eğitimler sonra.
    private var trainingGroups: [TrainingGroup] {
        let definitions: [(code: String, key: String, icon: String)] = [
            ("task_and_equipment", "analysis.result_hub.training.group.task_and_equipment", "wrench.and.screwdriver.fill"),
            ("qualification_and_authorization", "analysis.result_hub.training.group.qualification_and_authorization", "checkmark.seal.fill"),
            ("emergency_and_rescue", "analysis.result_hub.training.group.emergency_and_rescue", "cross.case.fill"),
            ("general_and_induction", "analysis.result_hub.training.group.general_and_induction", "person.badge.plus"),
            ("toolbox", "analysis.result_hub.training.group.toolbox", "megaphone.fill"),
        ]
        return definitions.compactMap { definition in
            let items = activeSection.items.filter { $0.groupCode == definition.code }
            guard !items.isEmpty else { return nil }
            return TrainingGroup(
                code: definition.code,
                label: localizedTrainingPromotion(definition.key),
                icon: definition.icon,
                items: items
            )
        }
    }

    /// Seçili ve hâlâ geçerli grup. `nil`, tüm eğitimleri gösterir.
    private func activeTrainingGroup(in groups: [TrainingGroup]) -> String? {
        if let selected = selectedTrainingGroup,
           groups.contains(where: { $0.code == selected }) {
            return selected
        }
        return nil
    }

    private func trainingGroupFilter(
        groups: [TrainingGroup],
        active: String?
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                trainingGroupChip(
                    label: copy(
                        "analysis.result_hub.training.group.all",
                        "Tümü",
                        "All"
                    ),
                    icon: "square.grid.2x2.fill",
                    count: activeSection.items.count,
                    selected: active == nil,
                    accessibilityID: "result.hub.training.group.all"
                ) {
                    selectedTrainingGroup = nil
                }

                ForEach(groups, id: \.code) { group in
                    let selected = group.code == active
                    trainingGroupChip(
                        label: group.label,
                        icon: group.icon,
                        count: group.items.count,
                        selected: selected,
                        accessibilityID: "result.hub.training.group.\(group.code)"
                    ) {
                        selectedTrainingGroup = group.code
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Yatay eğitim filtresindeki okunaklı, yüksek kontrastlı kategori rozeti.
    ///
    /// Dark modda yalnızca ince gri bir çizgiyle ayrılan eski etiketler kart
    /// yüzeyinde kayboluyordu. Mor ikon yuvası ve sayaç rozeti seçili olmayan
    /// durumda da kategorileri görünür tutuyor; seçim ise bölümün kendi
    /// gradyanını kullanarak netleşiyor.
    private func trainingGroupChip(
        label: String,
        icon: String,
        count: Int,
        selected: Bool,
        accessibilityID: String,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                onSelect()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(RDTypography.font(size: 10.5, weight: .bold))
                    .foregroundStyle(selected ? Color.white : Color.rdSectionTrainingAccent)
                    .frame(width: 24, height: 24)
                    .background(
                        selected
                            ? Color.white.opacity(0.18)
                            : Color.rdSectionTrainingTint
                    )
                    .clipShape(Circle())

                Text(label)
                    .font(referenceFont(11.5, selected ? .heavy : .bold))
                    .lineLimit(1)

                // The count is a distinct badge so it remains legible over
                // both the dark surface and the selected purple gradient.
                Text("\(count)")
                    .font(referenceFont(9.5, .heavy))
                    .foregroundStyle(selected ? Color.white : Color.rdSectionTrainingStrong)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 20)
                    .background(
                        selected
                            ? Color.white.opacity(0.18)
                            : Color.rdSectionTrainingTint
                    )
                    .clipShape(Capsule())
            }
            .foregroundStyle(selected ? Color.white : ink)
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .frame(height: 40)
            .background {
                if selected {
                    LinearGradient(
                        colors: [.rdSectionTrainingStart, .rdSectionTrainingAccent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Color.rdResultElevatedSurface
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(
                    selected
                        ? Color.white.opacity(0.16)
                        : Color.rdSectionTrainingAccent.opacity(0.68),
                    lineWidth: selected ? 1 : 1.25
                )
            }
            .shadow(
                color: selected
                    ? Color.rdSectionTrainingAccent.opacity(0.28)
                    : Color.black.opacity(0.08),
                radius: selected ? 5 : 2,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Eğitim kartı.
    ///
    /// Uzman görüşü kartıyla aynı gövde: aynı yüzey, aynı yeşil çerçeve, aynı
    /// köşedeki rozet. Farklı olan tek şey rozetin simgesi ve üst satırın
    /// bulgu numarası yerine kategoriyi taşıması -- burada numaralanacak bir
    /// bulgu yok, öneriyi tanımlayan şey türü.
    private func trainingCard(_ item: AnalysisResultHubItem) -> some View {
        let isLocked = isFreeTier || activeSection.access == .teaser

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    if let category = item.categoryLabel, !category.isEmpty {
                        Text(category.localizedUppercase)
                            .font(referenceFont(10, .heavy)).tracking(0.4)
                            .foregroundStyle(muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                if !isLocked {
                    Text(item.title ?? "")
                        .font(referenceFont(14, .black)).foregroundStyle(ink).padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)
                    if let audience = item.audienceLabel, !audience.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "person.2.fill")
                                .font(RDTypography.font(size: 10, weight: .semibold))
                            Text(audience)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(referenceFont(11, .medium))
                        .foregroundStyle(activeStrong)
                        .padding(.top, 7)
                    }
                    Text(item.text ?? "")
                        .font(referenceFont(12, .regular))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(3)
                        .padding(.top, 11)
                        .fixedSize(horizontal: false, vertical: true)

                    trainingDurationRow(item)
                } else {
                    trainingPremiumTeaserContent(item)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 13).padding(.top, 26).padding(.bottom, 16)
        }
        .background(Color.rdResultSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(activeAccent, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.10), radius: 7, x: 4, y: 6)
        .overlay(alignment: .topLeading) {
            Image(systemName: "graduationcap.fill")
                .font(RDTypography.font(size: 20, weight: .regular)).foregroundStyle(activeStrong)
                .frame(width: 36, height: 36).background(Color.rdResultSurface).clipShape(Circle()).offset(x: 15, y: -18)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isLocked else { return }
            openLockedTeaser(item)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.hub.training.card.\(item.id.uuidString)")
    }

    /// Hours and refresh interval, where the regulation fixes them.
    ///
    /// Only two trainings carry one, so most cards draw nothing here. The value
    /// names the workplace hazard class when the analysis is bound to a company
    /// that states it, and all three classes when it is not -- the backend
    /// decides which, because guessing a hazard class is exactly what it must
    /// not do.
    @ViewBuilder
    private func trainingDurationRow(_ item: AnalysisResultHubItem) -> some View {
        if let value = item.durationValue, !value.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(muted.opacity(0.22))
                    .frame(height: 1)
                    .padding(.top, 13)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(RDTypography.font(size: 10, weight: .semibold))
                        .foregroundStyle(muted)
                    VStack(alignment: .leading, spacing: 3) {
                        if let label = item.durationLabel, !label.isEmpty {
                            Text(label.localizedUppercase)
                                .font(referenceFont(9, .heavy)).tracking(0.4)
                                .foregroundStyle(muted)
                        }
                        Text(value)
                            .font(referenceFont(11, .semibold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = item.durationNote, !note.isEmpty {
                            Text(note)
                                .font(referenceFont(10, .regular))
                                .foregroundStyle(Color.rdResultSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 11)
            }
        }
    }

    private func trainingPremiumTeaserContent(_ item: AnalysisResultHubItem) -> some View {
        let title = normalizedSentenceText(item.title ?? "")
        let visibleTitle = firstWords(of: title, count: 2)

        return VStack(alignment: .leading, spacing: 9) {
            Text(visibleTitle)
                .font(referenceFont(14, .black))
                .foregroundStyle(ink)
                .lineLimit(1)

            ZStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(referenceFont(13, .bold))
                        .foregroundStyle(Color.rdResultPrimaryText)
                        .lineLimit(2)

                    if let audience = item.audienceLabel, !audience.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "person.2.fill")
                            Text(audience)
                        }
                        .font(referenceFont(11, .medium))
                        .foregroundStyle(activeStrong)
                        .lineLimit(2)
                    }

                    Text(item.text ?? "")
                        .font(referenceFont(12, .regular))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(4)
                        .lineLimit(5)

                    trainingDurationRow(item)
                }
                .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                .blur(radius: 5.5)
                .opacity(0.72)
                .accessibilityHidden(true)

                premiumTeaserCallout
            }
            .frame(maxWidth: .infinity, minHeight: 148)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(visibleTitle). \(copy("analysis.result_hub.v2.bu.ozellikler.premium.ozelliktir.8f8ba189", "Bu özellikler premium özelliktir", "These features are premium"))")
        .accessibilityIdentifier("result.hub.training.premium_teaser.\(item.id.uuidString)")
    }

    // MARK: Reference summaries    // MARK: Reference summaries

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
                Text(copy("analysis.result_hub.v2.toplam.bulgu.ba5791c2", "TOPLAM BULGU", "TOTAL FINDINGS"))
                    .font(referenceFont(10, .heavy)).tracking(0.4).foregroundStyle(.white.opacity(0.88))
                Text("\(activeSection.count)")
                    .font(referenceFont(30, .black)).tracking(-1.4).foregroundStyle(.white)
            }
            Rectangle().fill(.white.opacity(0.26)).frame(width: 1, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy("analysis.result_hub.v2.en.yuksek.skor.9364de00", "EN YÜKSEK SKOR", "HIGHEST SCORE"))
                    .font(referenceFont(10, .heavy)).tracking(0.4).foregroundStyle(.white.opacity(0.88))
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(scoreText(highest)).font(referenceFont(22, .black)).tracking(-1)
                    Text(method == .fineKinney ? copy("analysis.result_hub.v2.puan.1c38ab37", "puan", "points") : "/25")
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
            VStack(alignment: .trailing, spacing: 2) {
                Text(copy("analysis.result_hub.v2.dagilim.2a8e1c3d", "DAĞILIM", "DISTRIBUTION"))
                    .font(referenceFont(8.5, .heavy)).tracking(0.3).foregroundStyle(.white.opacity(0.88))
                    .padding(.bottom, 1)
                HStack(alignment: .bottom, spacing: 7) {
                    distributionBar(.critical, count: counts[.critical] ?? 0, maximum: maximumCount)
                    distributionBar(.high, count: counts[.high] ?? 0, maximum: maximumCount)
                    distributionBar(.medium, count: counts[.medium] ?? 0, maximum: maximumCount)
                    distributionBar(.low, count: counts[.low] ?? 0, maximum: maximumCount)
                }
                .frame(height: 43, alignment: .bottom)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 87)
        .background(
            ZStack {
                LinearGradient(colors: summaryGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.08)).frame(width: 84, height: 84).offset(x: 178, y: -35)
                Circle().fill(.white.opacity(0.05)).frame(width: 60, height: 60).offset(x: 90, y: 54)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(hex: "#142A4A").opacity(0.24), radius: 9, x: 4, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activeSection.count) \(copy("analysis.result_hub.v2.bulgu.f4632731", "bulgu", "findings")), \(copy("analysis.result_hub.v2.en.yuksek.skor.5ad84b21", "en yüksek skor", "highest score")) \(scoreText(highest))")
        .accessibilityIdentifier("result.hub.risk_summary")
    }

    private var nonRiskSummary: some View {
        let isExpert = selectedSection == .expertRecommendations
        let isTraining = selectedSection == .trainingRecommendations
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: isTraining
                  ? "graduationcap"
                  : isExpert ? "lightbulb" : "book.closed")
                .font(RDTypography.font(size: 20, weight: .regular)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(isTraining
                     ? copy("analysis.result_hub.v2.egitim.onerileri.6c816a03", "Eğitim Önerileri", "Training Recommendations")
                     : isExpert ? copy("analysis.result_hub.v2.uzman.gorusu.130b1c61", "Uzman Görüşü", "Expert Advice") : copy("analysis.result_hub.v2.onayl.defter.ca441ca5", "Onaylı Defter", "Safety Log"))
                    .font(referenceFont(16, .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                premiumPill
                Text(isTraining
                     ? copy("analysis.result_hub.v2.analizde.gorulen.tehlike.ve.ekipmanlara.go.ffeb2cda", "Analizde görülen tehlike ve ekipmanlara göre, ilgili çalışan gruplarına hangi eğitimlerin anlamlı olduğunu gösterir. Kişilerin mevcut belgeleri hakkında bir tespit içermez.", "Shows which training is meaningful for each group of workers, based on the hazards and equipment seen in the analysis. It makes no claim about anyone's existing certificates.")
                     : isExpert ? copy("analysis.result_hub.v2.analiz.yapt.g.n.z.fotograflar.ozelinde.uzm.8a305d0f", "Analiz yaptığınız fotoğraflar özelinde uzmanlık gerektiren bilgilerin yer aldığı alandır. İşyerinize uygunluğunu kontrol ediniz. PLUS ve PRO üyelerine özeldir.", "This area contains expert information specific to the photos you analyzed. Check that it is suitable for your workplace. Available exclusively to PLUS and PRO members.")
                     : copy("analysis.result_hub.v2.analiz.bulgular.ndan.uretilen.uzman.degerl.c8db360c", "Analiz bulgularından üretilen, uzman değerlendirmesine sunulan defter taslakları.", "Safety Log drafts created from analysis findings for expert review."))
                    .font(referenceFont(11, .medium)).foregroundStyle(.white.opacity(0.78)).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                Text("\(activeSection.count)").font(referenceFont(26, .black)).tracking(-1.2)
                Text(isTraining
                     ? copy("analysis.result_hub.v2.toplam.oneri.6cb82f74", "TOPLAM ÖNERİ", "TOTAL RECOMMENDATIONS")
                     : isExpert
                     ? copy("analysis.result_hub.v2.toplam.gorus.f284237a", "TOPLAM GÖRÜŞ", "TOTAL ADVICE")
                     : copy("analysis.result_hub.v2.toplam.kayit.ed2dc876", "TOPLAM KAYIT", "TOTAL ENTRIES"))
                    .font(referenceFont(9, .heavy)).tracking(0.4).foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(
            ZStack {
                LinearGradient(colors: summaryGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.08)).frame(width: 84, height: 84).offset(x: 180, y: -32)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: activeStrong.opacity(0.24), radius: 9, x: 4, y: 8)
    }

    private func distributionBar(_ level: RiskLevel, count: Int, maximum: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(referenceFont(8.5, .black)).foregroundStyle(.white)
            RoundedRectangle(cornerRadius: 3)
                .fill(summaryBarColor(level, active: count > 0))
                .frame(width: 11, height: max(2, CGFloat(count) / CGFloat(maximum) * 23))
            Text(shortRiskLabel(level))
                .font(referenceFont(7.5, .heavy)).tracking(0.15).foregroundStyle(.white.opacity(0.70))
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
            methodButton(.fineKinney, title: "Fine-Kinney", formula: localizedRiskFormula(.fineKinney, includesResult: true))
            methodButton(.matrix5x5, title: copy("analysis.result_hub.v2.5.5.matris.30882165", "5×5 Matris", "5×5 Matrix"), formula: localizedRiskFormula(.matrix5x5, includesResult: true))
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
                    if selected { Image(systemName: "checkmark").font(RDTypography.font(size: 9, weight: .black)) }
                    Text(title).font(referenceFont(11.5, selected ? .heavy : .bold))
                }
                Text(formula).font(referenceFont(8.5, .bold)).tracking(0.2)
            }
            .foregroundStyle(selected ? greenDark : Color.rdResultSecondaryText)
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(selected ? Color.rdResultSelectedSurface : Color.rdResultSubtleSurface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? green : Color.rdResultLine, lineWidth: selected ? 1.5 : 1))
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
                        Text(copy("analysis.result_hub.v2.sektor.299a6675", "Sektör:", "Sector:"))
                            .font(referenceFont(10.5, .bold)).foregroundStyle(Color.rdResultTertiaryText)
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
        .background(Color.rdResultGreenTint)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.rdResultLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.hub.analysis_info_card")
    }

    private func premiumDeepAnalysisCard(
        source item: AnalysisResultHubItem,
        position: Int
    ) -> some View {
        Button {
            requestPaywall(
                section: .riskAnalysis,
                placement: "results_feed_promotion",
                entryKind: "membership_promotion",
                promotionVariant: "plus_pro_deep_analysis",
                itemID: item.id.uuidString,
                afterItemCount: max(1, position - 1)
            )
        } label: {
            ZStack {
                premiumDeepAnalysisCardBody(source: item, position: position)
                    .blur(radius: 6)
                    .opacity(0.74)
                    .accessibilityHidden(true)

                premiumDeepAnalysisCallout
            }
            .frame(maxWidth: .infinity)
            .background(Color.rdResultSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(green, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.10), radius: 7, x: 4, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(premiumDeepAnalysisMessage)
        .accessibilityHint(copy("analysis.result_hub.v2.uyelik.seceneklerini.acar.6e331850", "Üyelik seçeneklerini açar", "Opens membership options"))
        .accessibilityIdentifier("result.hub.premium_deep_analysis_card")
    }

    private func premiumDeepAnalysisCardBody(
        source item: AnalysisResultHubItem,
        position: Int
    ) -> some View {
        let level = riskLevel(for: item)
        let score = method == .fineKinney ? item.fkScore : item.m5Score.map(Double.init)
        let action = correctiveActionText(for: item)
            ?? copy("analysis.result_hub.v2.tehlike.kaynag.izole.edilmeli.ve.guvenli.c.c73f25cf", "Tehlike kaynağı izole edilmeli ve güvenli çalışma yöntemi uygulanmalıdır.", "The hazard source should be isolated and a safe work method applied.")

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(methodRiskBandLabel(for: item, fallback: level))
                        .font(referenceFont(9.25, .heavy))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(referenceRiskColor(level))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(score.map(scoreText) ?? "—")
                            .font(referenceFont(14, .black))
                        Text(method == .fineKinney ? copy("analysis.result_hub.v2.puan.1c38ab37", "puan", "points") : "/25")
                            .font(referenceFont(9.5, .bold))
                            .foregroundStyle(Color.rdResultTertiaryText)
                    }
                    Spacer()
                    Text(copy("analysis.result_hub.v2.secili.9fce9c94", "Seçili", "Selected"))
                        .font(referenceFont(11, .heavy))
                        .foregroundStyle(greenDark)
                    Image(systemName: "checkmark.circle.fill")
                        .font(RDTypography.font(size: 23, weight: .semibold))
                        .foregroundStyle(green)
                }

                Text(item.displayTitle(language: language))
                    .font(referenceFont(15, .heavy))
                    .foregroundStyle(ink)
                    .lineSpacing(1)
                    .padding(.top, 12)
                    .lineLimit(2)

                Text(item.displayBody)
                    .font(referenceFont(12.5, .regular))
                    .foregroundStyle(muted)
                    .lineSpacing(3)
                    .padding(.top, 8)
                    .lineLimit(4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(RDTypography.font(size: 11, weight: .semibold))
                        Text(copy("analysis.result_hub.v2.duzeltici.onlem.18528a0f", "DÜZELTİCİ ÖNLEM", "CORRECTIVE ACTION"))
                            .font(referenceFont(9.5, .heavy))
                            .tracking(0.45)
                    }
                    .foregroundStyle(greenDark)
                    Text(firstSentence(of: action))
                        .font(referenceFont(11.5, .medium))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(2)
                        .lineLimit(3)
                    HStack(spacing: 5) {
                        Text(copy("analysis.result_hub.v2.devam.icin.t.klay.n.701eccbf", "Devamı için tıklayın", "Tap to continue"))
                            .font(referenceFont(10.5, .heavy))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(RDTypography.font(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(greenDark)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.rdResultGreenTintStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(green.opacity(0.30), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 12)

                HStack(spacing: 8) {
                    premiumFeatureTag(copy("analysis.result_hub.v2.kok.neden.a37f29be", "Kök Neden", "Root Cause"), color: Color(hex: "#F8E07A"))
                    premiumFeatureTag(copy("analysis.result_hub.v2.onleyici.faaliyet.36b02828", "Önleyici Faaliyet", "Preventive Action"), color: Color(hex: "#C8ECB0"))
                    premiumFeatureTag(copy("analysis.result_hub.v2.mevzuat.c73d9b7a", "Mevzuat", "Regulation"), color: Color(hex: "#BCD8F5"))
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 12)
            .padding(.top, 24)
            .padding(.bottom, 16)

            HStack(spacing: 18) {
                Image(systemName: "hand.thumbsup")
                Image(systemName: "hand.thumbsdown")
                Spacer()
                Text(copy("analysis.result_hub.v2.detaylar.513bcd14", "Detaylar", "Details"))
                Image(systemName: "chevron.right")
            }
            .font(referenceFont(11.5, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(green)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(RDTypography.font(size: 25, weight: .regular))
                    .foregroundStyle(referenceRiskColor(level))
                    .frame(width: 36, height: 36)
                Text("\(position) -")
                    .font(referenceFont(13, .black))
                    .foregroundStyle(Color.rdResultSecondaryText)
            }
            .padding(.trailing, 7)
            .background(Color.rdResultSurface)
            .clipShape(Capsule())
            .offset(x: 15, y: -18)
        }
    }

    private func premiumFeatureTag(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(RDTypography.font(size: 8, weight: .black))
                .foregroundStyle(Color(hex: "#3F8A56"))
            Text(title)
                .font(referenceFont(9.5, .heavy))
                .foregroundStyle(Color(hex: "#33403A"))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(color.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var premiumDeepAnalysisCallout: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Color(hex: "#E0A828"))
                Text("PLUS")
                    .foregroundStyle(Color(hex: "#A67C12"))
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 1, height: 16)
                Image(systemName: "star.fill")
                    .foregroundStyle(green)
                Text("PRO")
                    .foregroundStyle(greenDark)
            }
            .font(referenceFont(14, .black))

            Text(premiumDeepAnalysisMessage)
                .font(referenceFont(11, .semibold))
                .foregroundStyle(Color.rdResultSecondaryText)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: 310)
        .background(Color.rdResultElevatedSurface.opacity(0.97))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.6
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .shadow(color: Color.black.opacity(0.14), radius: 8, x: 2, y: 6)
    }

    private var premiumDeepAnalysisMessage: String {
        copy("analysis.result_hub.v2.bu.tehlike.derin.analiz.ve.derin.arast.rma.d1c985dd", "Bu tehlike derin analiz ve derin araştırma kullanılarak sadece PLUS/PRO üyeleri için üretilmiştir.", "This hazard was produced using deep analysis and deep research exclusively for PLUS/PRO members.")
    }

    @ViewBuilder
    private func trainingMembershipPromotion(afterItemCount: Int) -> some View {
        if isFreeTier {
            ResultMembershipPromotionCard(
                variant: .plusAndPro,
                title: localizedTrainingPromotion(
                    "analysis.result_hub.training.promotion.free.title"
                ),
                message: localizedTrainingPromotion(
                    "analysis.result_hub.training.promotion.free.message"
                ),
                actionTitle: localizedTrainingPromotion(
                    "analysis.result_hub.training.promotion.free.action"
                )
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                requestPaywall(
                    section: .trainingRecommendations,
                    placement: "results_feed_promotion",
                    entryKind: "membership_promotion",
                    promotionVariant: "plus_pro",
                    afterItemCount: afterItemCount
                )
            }
            .accessibilityHint(
                localizedTrainingPromotion(
                    "analysis.result_hub.training.promotion.free.accessibility_hint"
                )
            )
            .accessibilityIdentifier("result.hub.training.plus_pro_upgrade")
        } else if isPlusTier {
            proUpgradeCard(
                section: .trainingRecommendations,
                afterItemCount: afterItemCount
            )
        }
    }

    private func proUpgradeCard(
        section: AnalysisResultSectionID,
        afterItemCount: Int
    ) -> some View {
        let isTraining = section == .trainingRecommendations
        return ResultMembershipPromotionCard(
            variant: .pro,
            title: isTraining
                ? localizedTrainingPromotion(
                    "analysis.result_hub.training.promotion.pro.title"
                )
                : copy("analysis.result_hub.v2.analizini.pro.ile.guclendir.0f794053", "Analizini PRO ile güçlendir", "Power up your analysis with PRO"),
            message: proUpgradeMessage,
            actionTitle: copy("analysis.result_hub.v2.pro.ya.gec.b850bf0c", "PRO'ya geç", "Upgrade to PRO")
        ) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            requestPaywall(
                section: section,
                placement: "results_feed_promotion",
                entryKind: "membership_promotion",
                promotionVariant: "pro",
                afterItemCount: afterItemCount
            )
        }
        .accessibilityHint(copy("analysis.result_hub.v2.pro.abonelik.ekran.n.acar.9d0f7bfa", "PRO abonelik ekranını açar", "Opens the PRO subscription screen"))
        .accessibilityIdentifier("result.hub.pro_upgrade.\(section.rawValue)")
    }

    private var proUpgradeMessage: String {
        copy("analysis.result_hub.v2.analizlerinde.derin.arast.rma.ve.daha.gucl.fbc90452", "Analizlerinde Derin Araştırma ve daha güçlü yapay zekâ modellerinden yararlan. PRO’ya geç; sınırsız analiz seni bekliyor.", "Use Deep Research and more capable AI models in your analyses. Upgrade to PRO—unlimited analyses are waiting.")
    }

    private var selectionControls: some View {
        HStack {
            Text(selectedCountText).font(referenceFont(10.5, .bold)).foregroundStyle(Color.rdResultTertiaryText)
            Spacer()
            if activeSection.access == .full {
                Button {
                    let all = Set(activeSection.items.map(\.id))
                    selections[selectedSection] = selectedIDs.count == all.count ? [] : all
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(RDTypography.font(size: 10, weight: .black))
                        Text(selectedIDs.count == activeSection.items.count ? copy("analysis.result_hub.v2.tumunu.b.rak.8634f314", "Tümünü bırak", "Clear all") : copy("analysis.result_hub.v2.tumunu.sec.fa983a39", "Tümünü seç", "Select all"))
                            .font(referenceFont(11.5, .heavy))
                    }
                    .foregroundStyle(activeStrong)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedCountText: String {
        let unit: String
        switch selectedSection {
        case .riskAnalysis: unit = selectedIDs.count == 1 ? copy("analysis.result_hub.v2.bulgu.96a82c3c", "bulgu", "finding") : copy("analysis.result_hub.v2.bulgu.f4632731", "bulgu", "findings")
        case .expertRecommendations: unit = selectedIDs.count == 1 ? copy("analysis.result_hub.v2.gorus.4773142b", "görüş", "recommendation") : copy("analysis.result_hub.v2.gorus.3b700c2a", "görüş", "recommendations")
        case .approvedNotebook: unit = selectedIDs.count == 1 ? copy("analysis.result_hub.v2.kay.t.0506ad08", "kayıt", "entry") : copy("analysis.result_hub.v2.kay.t.1154bb1b", "kayıt", "entries")
        case .trainingRecommendations: unit = selectedIDs.count == 1 ? copy("analysis.result_hub.v2.oneri.86b1003f", "öneri", "recommendation") : copy("analysis.result_hub.v2.oneri.95a4dc92", "öneri", "recommendations")
        }
        return "\(selectedIDs.count)/\(activeSection.count) \(unit) \(copy("analysis.result_hub.v2.secili.59f2bc7b", "seçili", "selected"))"
    }

    // MARK: Finding cards

    private func riskCard(_ item: AnalysisResultHubItem, position: Int) -> some View {
        let level = riskLevel(for: item)
        let score = method == .fineKinney ? item.fkScore : item.m5Score.map(Double.init)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(methodRiskBandLabel(for: item, fallback: level))
                        .font(referenceFont(9.25, .heavy)).tracking(0.3).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(referenceRiskColor(level)).clipShape(RoundedRectangle(cornerRadius: 2))
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(score.map(scoreText) ?? "—").font(referenceFont(14, .black))
                        Text(method == .fineKinney ? copy("analysis.result_hub.v2.puan.1c38ab37", "puan", "points") : "/25")
                            .font(referenceFont(9.5, .bold)).foregroundStyle(Color.rdResultTertiaryText)
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
                if activeSection.access == .full {
                    correctiveActionPreview(item).padding(.top, 12)
                }
                featureTags(item).padding(.top, 12)
                if activeSection.access == .teaser { lockedContent(item).padding(.top, 12) }
            }
            .padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 16)
            if activeSection.access == .full { actionStrip(item) }
        }
        .background(Color.rdResultSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(activeAccent, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.10), radius: 7, x: 4, y: 6)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(RDTypography.font(size: 25, weight: .regular)).foregroundStyle(referenceRiskColor(level))
                    .frame(width: 36, height: 36)
                Text("\(position) -").font(referenceFont(13, .black)).foregroundStyle(Color.rdResultSecondaryText)
            }
            .padding(.trailing, 7).background(Color.rdResultSurface).clipShape(Capsule()).offset(x: 15, y: -18)
        }
        .contentShape(Rectangle())
        .onTapGesture { openDetails(item) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.hub.item.\(item.id.uuidString)")
    }

    @ViewBuilder
    private func correctiveActionPreview(_ item: AnalysisResultHubItem) -> some View {
        if let action = correctiveActionText(for: item) {
            Button { openDetails(item) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(RDTypography.font(size: 11, weight: .semibold))
                        Text(copy("analysis.result_hub.v2.duzeltici.onlem.18528a0f", "DÜZELTİCİ ÖNLEM", "CORRECTIVE ACTION"))
                            .font(referenceFont(9.5, .heavy))
                            .tracking(0.45)
                    }
                    .foregroundStyle(greenDark)

                    Text(firstSentence(of: action))
                        .font(referenceFont(11.5, .medium))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        Text(copy("analysis.result_hub.v2.devam.icin.t.klay.n.701eccbf", "Devamı için tıklayın", "Tap to continue"))
                            .font(referenceFont(10.5, .heavy))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(RDTypography.font(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(greenDark)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.rdResultGreenTintStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(green.opacity(0.30), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(copy("analysis.result_hub.v2.duzeltici.onlem.96ad612c", "Düzeltici önlem", "Corrective action")): \(firstSentence(of: action)). \(copy("analysis.result_hub.v2.devam.icin.t.klay.n.701eccbf", "Devamı için tıklayın", "Tap to continue"))")
            .accessibilityIdentifier("result.hub.item.corrective_preview.\(item.id.uuidString)")
        }
    }

    private func correctiveActionText(for item: AnalysisResultHubItem) -> String? {
        let measure = item.recommendedMeasures?
            .first(where: { $0.kind == .corrective })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let measure, !measure.isEmpty { return measure }

        let fallback = item.recommendedAction?.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback?.isEmpty == false ? fallback : nil
    }

    private func firstSentence(of text: String, maximumLength: Int = 170) -> String {
        let sentenceSource = normalizedSentenceText(text)

        if let punctuation = sentenceSource.firstIndex(where: { ".!?".contains($0) }) {
            return String(sentenceSource[...punctuation])
        }
        guard sentenceSource.count > maximumLength else { return sentenceSource }

        let boundary = sentenceSource.index(sentenceSource.startIndex, offsetBy: maximumLength)
        let prefix = sentenceSource[..<boundary]
        let shortened = prefix.split(separator: " ").dropLast().joined(separator: " ")
        return "\(shortened.isEmpty ? String(prefix) : shortened)…"
    }

    private func normalizedSentenceText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")

        let withoutListMarker = normalized
            .replacingOccurrences(
                of: #"^\s*(?:(?:\d+\s*[.):\-])|(?:\(\d+\))|[-•*])\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutListMarker.isEmpty ? normalized : withoutListMarker
    }

    private func premiumTeaserParts(of text: String) -> (first: String, continuation: String) {
        let normalized = normalizedSentenceText(text)
        let first = firstSentence(of: normalized)
        let visiblePrefix = first.hasSuffix("…") ? String(first.dropLast()) : first

        guard !visiblePrefix.isEmpty, normalized.hasPrefix(visiblePrefix) else {
            return (first, normalized)
        }

        let continuation = String(normalized.dropFirst(visiblePrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (first, continuation)
    }

    private func expertPremiumTeaserContent(_ item: AnalysisResultHubItem) -> some View {
        let title = normalizedSentenceText(item.displayTitle(language: language))
        let source = normalizedSentenceText(expertTeaserSource(for: item))
        let visibleTitle = firstWords(of: title, count: 2)

        return VStack(alignment: .leading, spacing: 9) {
            Text(visibleTitle)
                .font(referenceFont(14, .black))
                .foregroundStyle(ink)
                .lineLimit(1)

            ZStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(referenceFont(13, .bold))
                        .foregroundStyle(Color.rdResultPrimaryText)
                        .lineLimit(2)
                    Text(source)
                        .font(referenceFont(12, .regular))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(5)
                        .lineLimit(6)
                }
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                .blur(radius: 5.5)
                .opacity(0.72)
                .accessibilityHidden(true)

                premiumTeaserCallout
            }
            .frame(maxWidth: .infinity, minHeight: 128)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(visibleTitle). \(copy("analysis.result_hub.v2.bu.ozellikler.premium.ozelliktir.8f8ba189", "Bu özellikler premium özelliktir", "These features are premium"))")
        .accessibilityIdentifier("result.hub.item.premium_teaser.\(item.id.uuidString)")
    }

    private func firstWords(of text: String, count: Int) -> String {
        let words = normalizedSentenceText(text).split(whereSeparator: \Character.isWhitespace)
        let visible = words.prefix(max(1, count)).joined(separator: " ")
        return words.count > count ? "\(visible)…" : visible
    }

    private var premiumTeaserCallout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Color(hex: "#E0A828"))
                Text("PLUS")
                    .foregroundStyle(Color(hex: "#A67C12"))
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 1, height: 14)
                Image(systemName: "star.fill")
                    .foregroundStyle(green)
                Text("PRO")
                    .foregroundStyle(greenDark)
            }
            .font(referenceFont(12.5, .black))

            Text(copy("analysis.result_hub.v2.bu.ozellikler.premium.ozelliktir.cf363bbd", "Bu özellikler premium özelliktir.", "These features are premium."))
                .font(referenceFont(10.5, .semibold))
                .foregroundStyle(Color.rdResultSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.rdResultElevatedSurface.opacity(0.96))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.6
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .shadow(color: Color.black.opacity(0.12), radius: 7, x: 2, y: 5)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func expertCard(_ item: AnalysisResultHubItem, position: Int) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    HStack(spacing: 5) { Image(systemName: "photo"); Text("\(max(1, item.sourcePhotoIndices?.count ?? 1))") }
                        .font(referenceFont(10.5, .black)).foregroundStyle(Color.rdResultPrimaryText)
                        .padding(.horizontal, 7).padding(.vertical, 4).background(Color.rdResultSubtleSurface)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.rdResultLine, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text("\(copy("analysis.result_hub.v2.bulgu.192859cb", "BULGU", "FINDING")) #\(item.ordinal ?? position)")
                        .font(referenceFont(10, .heavy)).tracking(0.4).foregroundStyle(muted)
                    Spacer()
                    if activeSection.access == .full { selectionControl(item) }
                }
                if activeSection.access == .full {
                    Text(item.displayTitle(language: language))
                        .font(referenceFont(14, .black)).foregroundStyle(ink).padding(.top, 10)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = expertSummaryText(for: item) {
                        Text(summary)
                            .font(referenceFont(12, .regular)).foregroundStyle(Color.rdResultSecondaryText)
                            .lineSpacing(3).padding(.top, 6).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    expertRecommendationPreview(item).padding(.top, 13)
                } else {
                    expertPremiumTeaserContent(item)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 13).padding(.top, 26).padding(.bottom, 14)
            if activeSection.access == .full { actionStrip(item) }
        }
        .background(Color.rdResultSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(activeAccent, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.10), radius: 7, x: 4, y: 6)
        .overlay(alignment: .topLeading) {
            Image(systemName: "lightbulb")
                .font(RDTypography.font(size: 23, weight: .regular)).foregroundStyle(activeStrong)
                .frame(width: 36, height: 36).background(Color.rdResultSurface).clipShape(Circle()).offset(x: 15, y: -18)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if activeSection.access == .full {
                openDetails(item)
            } else {
                openLockedTeaser(item)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.hub.item.\(item.id.uuidString)")
    }

    private func expertSummaryText(for item: AnalysisResultHubItem) -> String? {
        guard let summary = item.description?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty
        else { return nil }
        guard summary != item.displayTitle(language: language) else { return nil }
        return summary
    }

    private func expertRecommendationText(for item: AnalysisResultHubItem) -> String? {
        let values = [
            item.recommendedMeasures?.first(where: { $0.kind == .corrective })?.text,
            item.recommendedAction,
            item.recommendationText,
            item.recommendedMeasures?.first(where: { $0.kind == .preventive })?.text,
        ]
        return values.compactMap { value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }.first
    }

    private func expertTeaserSource(for item: AnalysisResultHubItem) -> String {
        let values = [
            expertSummaryText(for: item),
            expertRecommendationText(for: item),
            item.rootCauseText,
            item.referencesText,
        ]
        let content = values.compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        return content.isEmpty ? item.displayBody : content.joined(separator: " ")
    }

    private func expertRecommendationPreview(_ item: AnalysisResultHubItem) -> some View {
        let recommendation = expertRecommendationText(for: item)
        return Button { openDetails(item) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let recommendation {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                            .font(RDTypography.font(size: 11, weight: .semibold))
                        Text(copy("analysis.result_hub.v2.uzman.onerisi.30a0f4e1", "UZMAN ÖNERİSİ", "EXPERT RECOMMENDATION"))
                            .font(referenceFont(9.5, .heavy))
                            .tracking(0.45)
                    }
                    .foregroundStyle(activeStrong)

                    Text(firstSentence(of: recommendation))
                        .font(referenceFont(11.5, .medium))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 5) {
                    Text(copy("analysis.result_hub.v2.devam.icin.t.klay.n.701eccbf", "Devamı için tıklayın", "Tap to continue"))
                        .font(referenceFont(10.5, .heavy))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(RDTypography.font(size: 12, weight: .semibold))
                }
                .foregroundStyle(activeStrong)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(activeTint)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(activeAccent.opacity(0.36), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            recommendation.map {
                "\(copy("analysis.result_hub.v2.uzman.onerisi.76e0e541", "Uzman önerisi", "Expert recommendation")): \(firstSentence(of: $0)). \(copy("analysis.result_hub.v2.devam.icin.t.klay.n.701eccbf", "Devamı için tıklayın", "Tap to continue"))"
            } ?? copy("analysis.result_hub.v2.devam.icin.t.klay.n.701eccbf", "Devamı için tıklayın", "Tap to continue")
        )
        .accessibilityIdentifier("result.hub.item.expert_preview.\(item.id.uuidString)")
    }

    private func featureTags(_ item: AnalysisResultHubItem) -> some View {
        let tags: [(label: String, color: Color, isAvailable: Bool)] = [
            (
                copy("analysis.result_hub.v2.kok.neden.a37f29be", "Kök Neden", "Root Cause"),
                Color(hex: "#F8E07A"),
                !(item.rootCauseText ?? "").isEmpty
            ),
            (
                copy("analysis.result_hub.v2.onleyici.faaliyet.36b02828", "Önleyici Faaliyet", "Preventive Action"),
                Color(hex: "#C8ECB0"),
                item.recommendedMeasures?.contains(where: { $0.kind == .preventive }) == true
            ),
            (
                copy("analysis.result_hub.v2.mevzuat.c73d9b7a", "Mevzuat", "Regulation"),
                Color(hex: "#BCD8F5"),
                !(item.referencesText ?? "").isEmpty
            )
        ]
        return WrappingHStack(spacing: 8) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                if tag.isAvailable {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(RDTypography.font(size: 8, weight: .black)).foregroundStyle(Color(hex: "#3F8A56"))
                        Text(tag.label).font(referenceFont(10.5, .heavy)).foregroundStyle(Color(hex: "#33403A"))
                    }
                    .padding(.horizontal, 3).padding(.vertical, 2).background(tag.color.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            Button { openDetails(item) } label: {
                Image(systemName: "chevron.right").font(RDTypography.font(size: 8, weight: .black)).foregroundStyle(greenMuted)
                    .frame(width: 20, height: 20).background(Color.rdResultSubtleSurface).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Notebook

    private var notebookPaper: some View {
        VStack(spacing: 0) {
            HStack {
                Text(copy("analysis.result_hub.v2.onayli.defter.kayitlari.9c4c236c", "ONAYLI DEFTER KAYITLARI", "SAFETY LOG ENTRIES"))
                    .font(referenceFont(9.5, .heavy)).tracking(0.7).foregroundStyle(activeStrong)
                Spacer()
                if activeSection.access == .teaser { Image(systemName: "lock.fill").foregroundStyle(activeStrong) }
            }
            .padding(.leading, 50).padding(.trailing, 15).padding(.vertical, 15)
            .background(activeTint)
            VStack(spacing: 27) {
                if activeSection.access == .teaser {
                    notebookPremiumTeaser
                } else {
                    ForEach(Array(activeSection.items.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(index + 1)-").font(referenceFont(13, .heavy)).foregroundStyle(activeStrong)
                                .frame(width: 17, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notebookCombinedText(item))
                                    .font(referenceFont(12.5, .medium)).foregroundStyle(Color.rdResultPrimaryText)
                                    .lineSpacing(11)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 50).padding(.trailing, 15).padding(.vertical, 12)
            .background(NotebookRuledBackground(paper: Color.rdResultKhakiTint, line: Color.rdResultLine))
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy("analysis.result_hub.v2.uzman.degerlendirmesi.78eb5c8a", "UZMAN DEĞERLENDİRMESİ", "EXPERT REVIEW"))
                        .font(referenceFont(9.5, .heavy)).tracking(0.5).foregroundStyle(activeStrong)
                    Text(copy("analysis.result_hub.v2.bu.kay.t.bir.taslakt.r.59c2ed4b", "Bu kayıt bir taslaktır", "This entry is a draft"))
                        .font(referenceFont(12, .bold)).foregroundStyle(Color.rdResultPrimaryText)
                }
                Spacer()
                VStack(spacing: 1) {
                    Text(copy("analysis.result_hub.v2.taslak.688eaadb", "TASLAK", "DRAFT")).font(referenceFont(8.5, .heavy)).tracking(0.5)
                    Text(copy("analysis.result_hub.v2.uzman.onayi.75f9b460", "UZMAN ONAYI", "EXPERT REVIEW")).font(referenceFont(8, .bold))
                }
                .foregroundStyle(activeStrong).frame(width: 74, height: 74)
                .overlay(Circle().stroke(activeAccent.opacity(0.62), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .rotationEffect(.degrees(-8))
            }
            .padding(.leading, 50).padding(.trailing, 15).padding(.vertical, 12)
            .background(activeTint)
        }
        .overlay(alignment: .leading) {
            LinearGradient(colors: [activeAccent.opacity(0.58), activeAccent.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 7)
            Rectangle().fill(activeAccent.opacity(0.58)).frame(width: 1.5).offset(x: 38)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(activeAccent.opacity(0.50), lineWidth: 1.2))
        .clipShape(NotebookOuterShape())
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 5, y: 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard activeSection.access == .teaser, let first = activeSection.items.first else { return }
            openLockedTeaser(first)
        }
    }

    @ViewBuilder
    private var notebookPremiumTeaser: some View {
        if let first = activeSection.items.first {
            let firstParts = premiumTeaserParts(of: notebookTeaserSource(for: first))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    Text("1-")
                        .font(referenceFont(13, .heavy))
                        .foregroundStyle(activeStrong)
                        .frame(width: 17, alignment: .trailing)
                    Text(firstParts.first)
                        .font(referenceFont(12.5, .medium))
                        .foregroundStyle(Color.rdResultPrimaryText)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ZStack {
                    VStack(alignment: .leading, spacing: 16) {
                        if !firstParts.continuation.isEmpty {
                            HStack(alignment: .top, spacing: 9) {
                                Color.clear.frame(width: 17, height: 1)
                                Text(firstParts.continuation)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        ForEach(Array(activeSection.items.dropFirst().enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 9) {
                                Text("\(index + 2)-")
                                    .font(referenceFont(13, .heavy))
                                    .foregroundStyle(activeStrong)
                                    .frame(width: 17, alignment: .trailing)
                                Text(notebookTeaserSource(for: item))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .font(referenceFont(12.5, .medium))
                    .foregroundStyle(Color.rdResultPrimaryText)
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
                    .blur(radius: 4.5)
                    .opacity(0.76)
                    .accessibilityHidden(true)

                    premiumTeaserCallout
                }
                .frame(maxWidth: .infinity, minHeight: 154)
                .clipped()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(firstParts.first). \(copy("analysis.result_hub.v2.bu.ozellikler.premium.ozelliktir.8f8ba189", "Bu özellikler premium özelliktir", "These features are premium"))")
            .accessibilityIdentifier("result.hub.notebook.premium_teaser")
        }
    }

    private func notebookTeaserSource(for item: AnalysisResultHubItem) -> String {
        let values = [item.findingText, item.recommendationText, item.referenceText]
        let content = values.compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        return content.joined(separator: " ")
    }

    private func notebookCombinedText(_ item: AnalysisResultHubItem) -> String {
        let finding = item.findingText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let recommendation = item.recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if activeSection.access == .teaser { return finding }
        // Onaylı defter metni tek akıcı paragraftır; "Tespit:"/"Öneri:" gibi
        // rapor etiketleri taşımaz. Öneri alanı boşsa metin zaten bu biçimdedir.
        if recommendation.isEmpty { return finding }
        var result = "\(copy("analysis.result_hub.v2.tespit.dadc9d63", "Tespit:", "Finding:")) \(finding) \(copy("analysis.result_hub.v2.oneri.d5e11e40", "Öneri:", "Recommendation:")) \(recommendation)"
        let basis = (item.referenceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !basis.isEmpty { result += " \(copy("analysis.result_hub.v2.dayanak.e604d06c", "Dayanak:", "Basis:")) \(basis)" }
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
                    Text(selected ? copy("analysis.result_hub.v2.secildi.7fb687e3", "Seçildi", "Selected") : copy("analysis.result_hub.v2.sec.0abbb5fb", "Seç", "Select"))
                        .font(referenceFont(11.5, .heavy)).foregroundStyle(selected ? activeStrong : Color.rdResultTertiaryText)
                }
                Image(systemName: selected ? "checkmark" : "")
                    .font(RDTypography.font(size: 10, weight: .black)).foregroundStyle(Color.white)
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .background(selected ? activeAccent : Color.rdResultSurface)
                    .overlay(Circle().stroke(selected ? activeAccent : Color.rdResultLine, lineWidth: 1.5))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? copy("analysis.result_hub.v2.rapordan.c.kar.7c294954", "Rapordan çıkar", "Remove from report") : copy("analysis.result_hub.v2.rapora.ekle.f54c4bf7", "Rapora ekle", "Add to report"))
    }

    private func actionStrip(_ item: AnalysisResultHubItem) -> some View {
        HStack(spacing: 2) {
            if activeSection.canEdit {
                stripButton("pencil", label: copy("analysis.result_hub.v2.duzenle.3248ed57", "Düzenle", "Edit")) { edit(item) }
                stripButton("trash", label: copy("analysis.result_hub.v2.sil.c0b0d3c6", "Sil", "Delete")) { delete(item) }
            }
            stripButton(reaction(for: item) == .like ? "hand.thumbsup.fill" : "hand.thumbsup", label: copy("analysis.result_hub.v2.begen.829db692", "Beğen", "Like")) {
                toggleReaction(item, reaction: .like)
            }
            stripButton(reaction(for: item) == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", label: copy("analysis.result_hub.v2.begenme.627f80ac", "Beğenme", "Dislike")) {
                if reaction(for: item) == .dislike { toggleReaction(item, reaction: .dislike) }
                else {
                    feedbackComposerExpanded = false
                    pendingDislike = item
                }
            }
            Spacer(minLength: 0)
            Button { openDetails(item) } label: {
                HStack(spacing: 5) { Text(copy("analysis.result_hub.v2.detaylar.513bcd14", "Detaylar", "Details")); Image(systemName: "chevron.right") }
                    .font(referenceFont(11.5, .heavy)).foregroundStyle(.white).padding(.horizontal, 4).frame(height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("result.hub.item.details.\(item.id.uuidString)")
        }
        .padding(.horizontal, 10).frame(height: 48).background(activeAccent)
    }

    private func stripButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(RDTypography.font(size: 17, weight: .regular)).foregroundStyle(.white).frame(width: 34, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func openLockedTeaser(_ item: AnalysisResultHubItem) {
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
        requestPaywall(
            section: selectedSection,
            placement: "locked_content_teaser",
            entryKind: "content_gate",
            itemID: item.id.uuidString
        )
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
                openLockedTeaser(item)
            } label: {
                HStack(spacing: 7) { Image(systemName: "lock.open.fill"); Text(copy("analysis.result_hub.v2.plus.pro.ile.tamam.n.ac.8257a71f", "Plus / Pro ile tamamını aç", "Unlock all with Plus / Pro")) }
                    .font(referenceFont(12, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10).background(activeStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Bottom report CTA

    private var reportBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                bottomBackButton
                reportActionButton
            }
            if selectedSection != .approvedNotebook {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 66, height: 1)
                    Text(selectedCountText)
                        .font(referenceFont(10.5, .bold))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 9).padding(.bottom, 18)
        .background(Color.rdResultElevatedSurface.shadow(.drop(color: Color.black.opacity(0.22), radius: 9, y: -6)))
    }

    private var bottomBackButton: some View {
        Button(action: onBack) {
            VStack(spacing: 1) {
                Image(systemName: "chevron.left")
                    .font(RDTypography.font(size: 15, weight: .black))
                Text(copy("analysis.result_hub.v2.geri.don.be8542b6", "Geri Dön", "Go Back"))
                    .font(referenceFont(8.5, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(activeStrong)
            .frame(width: 66, height: 50)
            .background(activeTint)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(activeAccent.opacity(0.48), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: activeStrong.opacity(0.12), radius: 6, x: 2, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copy("analysis.result_hub.v2.geri.don.1ff1d53c", "Geri dön", "Go back"))
        .accessibilityIdentifier("result.hub.bottom_back")
    }

    private var reportActionButton: some View {
        Button {
            if activeSection.access == .teaser || !activeSection.canReport {
                requestPaywall(
                    section: selectedSection,
                    placement: "sticky_report_cta",
                    entryKind: "report_gate"
                )
            } else if !selectedIDs.isEmpty {
                reportKind = selectedSection == .riskAnalysis ? nil : .section
                reportFormat = "pdf"
                let initialHeight = ReferenceReportSheetLayout.initialHeight(for: selectedSection)
                reportSheetHeight = initialHeight
                reportSheetDetent = .height(initialHeight)
                reportSheetPresented = true
            }
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: activeSection.access == .teaser ? "lock.fill" : "slider.horizontal.3")
                        .font(RDTypography.font(size: 18, weight: .regular))
                    Text(activeSection.access == .teaser ? copy("analysis.result_hub.v2.plus.pro.ile.ac.ad2bd639", "Plus / Pro ile Aç", "Unlock with Plus / Pro") : copy("analysis.result_hub.v2.rapor.olustur.e0a43f76", "Rapor Oluştur", "Create Report"))
                        .font(referenceFont(15.5, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity)
                Image(systemName: "paperplane.fill")
                    .font(RDTypography.font(size: 17, weight: .regular)).foregroundStyle(Color(hex: "#111111"))
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
                            ? copy("analysis.result_hub.v2.plus.pro.ile.ac.ad2bd639", "Plus / Pro ile Aç", "Unlock with Plus / Pro")
                            : selectedSection == .approvedNotebook
                                ? copy("analysis.result_hub.v2.rapor.olustur.e0a43f76", "Rapor Oluştur", "Create Report")
                                : "\(copy("analysis.result_hub.v2.rapor.olustur.e0a43f76", "Rapor Oluştur", "Create Report")) · \(selectedIDs.count)/\(activeSection.count)")
        .accessibilityIdentifier("result.hub.report")
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
        case .critical: copy("analysis.result_hub.v2.kritik.risk.091ca59c", "KRİTİK RİSK", "CRITICAL RISK")
        case .high: copy("analysis.result_hub.v2.yuksek.risk.e8e28270", "YÜKSEK RİSK", "HIGH RISK")
        case .medium: copy("analysis.result_hub.v2.orta.risk.a014ee49", "ORTA RİSK", "MEDIUM RISK")
        case .low: copy("analysis.result_hub.v2.dusuk.risk.9bdc8549", "DÜŞÜK RİSK", "LOW RISK")
        case .unknown: copy("analysis.result_hub.v2.degerlendirilmedi.067ca5b9", "DEĞERLENDİRİLMEDİ", "UNASSESSED")
        }
    }
    private func methodRiskBandLabel(for item: AnalysisResultHubItem, fallback level: RiskLevel) -> String {
        let label: String
        switch method {
        case .fineKinney:
            guard let score = item.fkScore else { return riskBandLabel(level) }
            switch score {
            case 401...:
                label = RDLocalization.string("analysis.finding.tolerans.disi.3f8f17ca", table: .analysis, fallback: "Tolerans dışı", language: language)
            case 201...400:
                label = RDLocalization.string("analysis.finding.yuksek.risk.7384eb4f", table: .analysis, fallback: "Yüksek risk", language: language)
            case 71...200:
                label = RDLocalization.string("analysis.finding.onemli.risk.e4e46a8b", table: .analysis, fallback: "Önemli risk", language: language)
            case 21...70:
                label = RDLocalization.string("analysis.finding.olasi.risk.61fdb63e", table: .analysis, fallback: "Olası risk", language: language)
            default:
                label = RDLocalization.string("analysis.finding.onemsiz.ca1e144e", table: .analysis, fallback: "Önemsiz", language: language)
            }
        case .matrix5x5:
            guard let score = item.m5Score else { return riskBandLabel(level) }
            switch score {
            case 20...:
                label = RDLocalization.string("analysis.finding.tolerans.disi.d50498c6", table: .analysis, fallback: "Tolerans dışı", language: language)
            case 10...19:
                label = RDLocalization.string("analysis.finding.yuksek.risk.56653260", table: .analysis, fallback: "Yüksek risk", language: language)
            case 5...9:
                label = RDLocalization.string("analysis.finding.orta.risk.6902fcc6", table: .analysis, fallback: "Orta risk", language: language)
            case 3...4:
                label = RDLocalization.string("analysis.finding.dusuk.risk.cca91a7e", table: .analysis, fallback: "Düşük risk", language: language)
            default:
                label = RDLocalization.string("analysis.finding.onemsiz.9db630ac", table: .analysis, fallback: "Önemsiz", language: language)
            }
        }
        return label.uppercased(with: language.locale)
    }
    private func shortRiskLabel(_ level: RiskLevel) -> String {
        switch level {
        case .critical: copy("analysis.result_hub.v2.krt.4da4bdb1", "KRT", "CRT")
        case .high: copy("analysis.result_hub.v2.ysk.b21595ae", "YSK", "HGH")
        case .medium: copy("analysis.result_hub.v2.ort.339c6d29", "ORT", "MED")
        case .low: copy("analysis.result_hub.v2.dsk.94153e92", "DŞK", "LOW")
        case .unknown: "?"
        }
    }
    private func scoreText(_ score: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: score)) ?? String(score)
    }
    private func localizedRiskFormula(_ method: RiskMethod, includesResult: Bool = false) -> String {
        let factors: String
        switch method {
        case .fineKinney:
            factors = RDLocalization.string(
                "analysis.finding.o.f.s.1a128241",
                table: .analysis,
                fallback: "O × F × Ş",
                language: language
            )
        case .matrix5x5:
            factors = RDLocalization.string(
                "analysis.finding.o.s.e9e53958",
                table: .analysis,
                fallback: "O × Ş",
                language: language
            )
        }
        return includesResult ? "R = \(factors)" : factors
    }
    private func reaction(for item: AnalysisResultHubItem) -> AnalysisItemReaction {
        reactions[item.id] ?? item.userReaction ?? AnalysisItemReaction.none
    }
    private func openDetails(_ item: AnalysisResultHubItem) {
        switch selectedSection {
        case .riskAnalysis, .expertRecommendations:
            onOpenFinding(item.asFindingRow(fallbackAnalysisID: analysisID), selectedSection)
        case .approvedNotebook:
            detailItem = item
        case .trainingRecommendations:
            // Eğitim kartının kendisi zaten tam metin; açılacak bir detay yok.
            break
        }
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
        let previous = self.reaction(for: item)
        let next: AnalysisItemReaction = previous == reaction ? .none : reaction
        let section = selectedSection
        reactions[item.id] = next
        Task {
            do {
                try await AnalysisResultHubService.shared.setFeedback(
                    analysisID: analysisID,
                    language: language,
                    section: section,
                    item: item,
                    reaction: next
                )
                await AnalysisResultHubService.shared.recordEvent(
                    analysisID: analysisID,
                    language: language,
                    name: next == .none ? "result_feedback_cleared" : "result_feedback_set",
                    section: section,
                    itemID: item.id,
                    funnelSessionID: funnelSessionID
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                if reactions[item.id] == next { reactions[item.id] = previous }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
    @MainActor
    private func submitDislike(item: AnalysisResultHubItem, reason: String?, note: String?) async -> Bool {
        let section = selectedSection
        do {
            try await AnalysisResultHubService.shared.setFeedback(
                analysisID: analysisID,
                language: language,
                section: section,
                item: item,
                reaction: .dislike,
                reason: reason,
                note: note
            )
            reactions[item.id] = .dislike
            await AnalysisResultHubService.shared.recordEvent(
                analysisID: analysisID,
                language: language,
                name: "result_feedback_set",
                section: section,
                itemID: item.id,
                funnelSessionID: funnelSessionID
            )
            showFeedbackThanksToast()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    private func showFeedbackThanksToast() {
        let token = UUID()
        withAnimation { feedbackToastToken = token }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard feedbackToastToken == token else { return }
            withAnimation { feedbackToastToken = nil }
        }
    }
    private func initializeState() {
        for section in hub.sections {
            if selections[section.id] == nil { selections[section.id] = section.access == .full ? Set(section.items.map(\.id)) : [] }
            for item in section.items { reactions[item.id] = item.userReaction ?? AnalysisItemReaction.none }
        }
    }

    private func syncReactionsFromHub() {
        for section in hub.sections {
            for item in section.items {
                reactions[item.id] = item.userReaction ?? AnalysisItemReaction.none
            }
        }
    }

    private func notebookEditor(_ item: AnalysisResultHubItem) -> some View {
        // Defter metni tek paragrafsa tek alanda düzenlenir. İki alanlı biçim
        // eski projeksiyona ait; boş bir "Öneri" kutusu göstermek kullanıcıya
        // doldurması gereken bir yer varmış gibi görünür.
        let singleParagraph = (item.recommendationText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return NavigationStack {
            Form {
                if singleParagraph {
                    Section(copy("analysis.result_hub.v2.kay.t.metni.021163e0", "Kayıt metni", "Entry text")) {
                        TextEditor(text: $notebookFindingDraft).frame(minHeight: 220)
                    }
                } else {
                    Section(copy("analysis.result_hub.v2.tespit.4e395ed8", "Tespit", "Finding")) { TextEditor(text: $notebookFindingDraft).frame(minHeight: 120) }
                    Section(copy("analysis.result_hub.v2.oneri.cbecd1fc", "Öneri", "Recommendation")) { TextEditor(text: $notebookRecommendationDraft).frame(minHeight: 150) }
                }
                Section {
                    Text(copy("analysis.result_hub.v2.bu.icerik.onayl.defter.taslag.d.r.uzman.de.c7716412", "Bu içerik Onaylı Defter taslağıdır; uzman değerlendirmesi gerekir.", "This is a Safety Log draft and requires expert review."))
                        .font(RDTypography.font(.footnote)).foregroundStyle(Color.rdSlate)
                }
            }
            .navigationTitle(copy("analysis.result_hub.v2.defter.taslag.n.duzenle.623cec17", "Defter Taslağını Düzenle", "Edit Safety Log Draft"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(copy("analysis.result_hub.v2.vazgec.583c4eba", "Vazgeç", "Cancel")) { editingNotebook = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("analysis.result_hub.v2.kaydet.2418617f", "Kaydet", "Save")) {
                        onEditNotebook(item, notebookFindingDraft, notebookRecommendationDraft)
                        editingNotebook = nil
                    }
                    .disabled(
                        notebookFindingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (!singleParagraph && notebookRecommendationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
        }
    }

    private var premiumPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").foregroundStyle(Color(hex: "#E0A828"))
            Text("PLUS").foregroundStyle(Color(hex: "#A67C12")).lineLimit(1)
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 1, height: 9)
            Image(systemName: "star.fill").foregroundStyle(green)
            Text("PRO").foregroundStyle(greenDark).lineLimit(1)
        }
        .font(referenceFont(9, .black)).padding(.horizontal, 8).padding(.vertical, 3).background(Color.rdResultElevatedSurface)
        .clipShape(Capsule()).padding(1.5)
        .background(LinearGradient(colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")], startPoint: .leading, endPoint: .trailing))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var emptyState: some View {
        let content: (icon: String, title: String, message: String) = switch selectedSection {
        case .riskAnalysis:
            (
                "checkmark.shield",
                copy("analysis.result_hub.v2.bu.analizde.risk.bulgusu.bulunamad.baa0920b", "Bu analizde risk bulgusu bulunamadı", "No risk findings in this analysis"),
                copy("analysis.result_hub.v2.yuklediginiz.fotograflarda.raporlanabilir..bd7b16f9", "Yüklediğiniz fotoğraflarda raporlanabilir bir risk tespit edilmedi. Saha kontrolünüzü yine de sürdürün.", "No reportable risk was detected in the uploaded photos. Continue your on-site checks as usual.")
            )
        case .expertRecommendations:
            (
                "person.badge.shield.checkmark",
                copy("analysis.result_hub.v2.uzman.gorusu.bulunmuyor.25287788", "Uzman görüşü bulunmuyor", "No expert advice available"),
                copy("analysis.result_hub.v2.bu.analiz.icin.uygun.bir.uzman.gorusu.olus.bc24b708", "Bu analiz için uygun bir uzman görüşü oluşturulmadı.", "No applicable expert advice was generated for this analysis.")
            )
        case .approvedNotebook:
            (
                "book.closed",
                copy("analysis.result_hub.v2.onayl.defter.kayd.bulunmuyor.8764fde9", "Onaylı defter kaydı bulunmuyor", "No Safety Log entries available"),
                copy("analysis.result_hub.v2.bu.analiz.icin.uygun.bir.onayl.defter.tasl.66596eba", "Bu analiz için uygun bir onaylı defter taslağı oluşturulmadı.", "No applicable Safety Log draft was generated for this analysis.")
            )
        case .trainingRecommendations:
            (
                "graduationcap",
                copy("analysis.result_hub.v2.egitim.onerisi.bulunmuyor.03b337b9", "Eğitim önerisi bulunmuyor", "No training recommendations"),
                copy("analysis.result_hub.v2.bu.analizde.egitim.onerisi.uretecek.bir.te.bcd77c08", "Bu analizde eğitim önerisi üretecek bir tehlike veya ekipman tanınmadı.", "No hazard or equipment in this analysis produced a training recommendation.")
            )
        }

        return VStack(spacing: 10) {
            Image(systemName: content.icon)
                .font(RDTypography.font(size: 28, weight: .medium))
                .foregroundStyle(activeStrong)
            Text(content.title)
                .font(referenceFont(14, .heavy))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
            Text(content.message)
                .font(referenceFont(12, .regular))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .background(activeTint)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(activeAccent.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.hub.empty_state.\(selectedSection.rawValue)")
    }
    private func requestPaywall(
        section: AnalysisResultSectionID,
        placement: String,
        entryKind: String,
        promotionVariant: String? = nil,
        itemID: String? = nil,
        afterItemCount: Int? = nil
    ) {
        var attributes = [
            "entry_kind": entryKind,
            "placement": placement,
            "source_section": section.rawValue,
            "current_tier": (hub.tier ?? "unknown").lowercased(),
        ]
        if let promotionVariant {
            attributes["promotion_variant"] = promotionVariant
        }
        if let afterItemCount {
            attributes["after_item_count"] = String(afterItemCount)
        }

        onPaywall(
            AnalysisResultPaywallRequest(
                section: section,
                funnelSessionID: funnelSessionID,
                itemID: itemID,
                attributes: attributes
            )
        )
    }

    private func localizedTrainingPromotion(_ key: String) -> String {
        RDLocalization.string(
            key,
            table: .analysis,
            fallback: key,
            language: language
        )
    }

    private func copy(_ key: String, _ turkish: String, _ english: String) -> String {
        RDLocalization.string(key, table: .analysis, fallback: language == .turkish ? turkish : english, language: language)
    }
    private func referenceFont(_ size: CGFloat, _ weight: Font.Weight) -> Font { RDTypography.font(size, weight) }
}

enum ResultMembershipPromotionVariant: Equatable {
    case pro
    case plusAndPro
}

struct ResultMembershipPromotionCard: View {
    let variant: ResultMembershipPromotionVariant
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                promotionIcon

                VStack(alignment: .leading, spacing: 7) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            promotionTitle
                            planBadges
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            promotionTitle
                            planBadges
                        }
                    }

                    Text(message)
                        .font(RDTypography.font(size: 11.25, weight: .medium))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        Text(actionTitle)
                            .font(RDTypography.font(size: 10.5, weight: .heavy))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(RDTypography.font(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(actionGradient)
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "#4B68C8").opacity(0.20), radius: 5, x: 0, y: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(RDTypography.font(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "#6656E8"))
                    .padding(.top, 15)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderGradient, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color(hex: "#6656E8").opacity(0.16), radius: 11, x: 0, y: 7)
            .shadow(color: Color(hex: "#168FC7").opacity(0.10), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(actionTitle). \(message)")
    }

    private var promotionTitle: some View {
        Text(title)
            .font(RDTypography.font(size: 14, weight: .black))
            .foregroundStyle(Color.rdResultPrimaryText)
            .lineLimit(variant == .pro ? 1 : 2)
            .minimumScaleFactor(0.78)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var promotionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconGradient)
            if variant == .pro {
                Image(systemName: "star.fill")
                    .font(RDTypography.font(size: 18, weight: .heavy))
            } else {
                HStack(spacing: 1) {
                    Image(systemName: "crown.fill")
                    Image(systemName: "star.fill")
                }
                .font(RDTypography.font(size: 12, weight: .heavy))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .shadow(color: Color(hex: "#7259F5").opacity(0.28), radius: 9, x: 0, y: 5)
    }

    @ViewBuilder
    private var planBadges: some View {
        HStack(spacing: 5) {
            if variant == .plusAndPro {
                planBadge(
                    "PLUS",
                    icon: "crown.fill",
                    colors: [Color(hex: "#F0A400"), Color(hex: "#E8762A")]
                )
            }
            planBadge(
                "PRO",
                icon: "star.fill",
                colors: [Color(hex: "#7259F5"), Color(hex: "#168FC7"), Color(hex: "#00AE73")]
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func planBadge(_ text: String, icon: String, colors: [Color]) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(RDTypography.font(size: 7.5, weight: .black))
            Text(text)
                .font(RDTypography.font(size: 8.5, weight: .black))
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(Capsule())
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: variant == .pro
                ? [Color(hex: "#7259F5"), Color(hex: "#168FC7"), Color(hex: "#00AE73")]
                : [Color(hex: "#F0A400"), Color(hex: "#E8762A"), Color(hex: "#7259F5"), Color(hex: "#168FC7")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var actionGradient: LinearGradient {
        LinearGradient(
            colors: variant == .pro
                ? [Color(hex: "#6656E8"), Color(hex: "#168FC7"), Color(hex: "#00A86B")]
                : [Color(hex: "#D88A00"), Color(hex: "#7259F5"), Color(hex: "#168FC7"), Color(hex: "#00A86B")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: variant == .pro
                ? [Color(hex: "#7259F5"), Color(hex: "#168FC7"), Color(hex: "#00AE73")]
                : [Color(hex: "#F0A400"), Color(hex: "#E8762A"), Color(hex: "#7259F5"), Color(hex: "#168FC7"), Color(hex: "#00AE73")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: variant == .pro
                    ? [Color.rdResultElevatedSurface, Color.rdResultBlueTint, Color.rdResultMintTint]
                    : [Color.rdResultAmberTint, Color.rdResultElevatedSurface, Color.rdResultBlueTint, Color.rdResultMintTint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(hex: "#7259F5").opacity(0.10))
                .frame(width: 118, height: 118)
                .offset(x: 150, y: -56)
            Circle()
                .fill((variant == .pro ? Color(hex: "#00AE73") : Color(hex: "#F0A400")).opacity(0.09))
                .frame(width: 92, height: 92)
                .offset(x: -165, y: 66)
        }
    }
}

// MARK: Feedback panel

private struct FeedbackReasonOption: Identifiable {
    let code: String
    let localizationKey: String
    var id: String { code }
}

struct DislikeFeedbackPanel: View {
    let language: RDLanguage
    @Binding var isComposerExpanded: Bool
    let onClose: () -> Void
    let onSubmit: (String?, String?) async -> Bool

    @FocusState private var noteFocused: Bool
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var showsError = false

    private let green = Color.rdResultGreen
    private let greenDark = Color.rdResultGreenDark
    private let ink = Color.rdResultPrimaryText
    private let muted = Color.rdResultSecondaryText
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]
    private let reasons = [
        FeedbackReasonOption(code: "incorrect_detection", localizationKey: "analysis.result_hub.feedback.reason.incorrect_detection"),
        FeedbackReasonOption(code: "missing_context", localizationKey: "analysis.result_hub.feedback.reason.missing_context"),
        FeedbackReasonOption(code: "wrong_score", localizationKey: "analysis.result_hub.feedback.reason.wrong_score"),
        FeedbackReasonOption(code: "wrong_recommendation", localizationKey: "analysis.result_hub.feedback.reason.wrong_recommendation"),
        FeedbackReasonOption(code: "duplicate", localizationKey: "analysis.result_hub.feedback.reason.duplicate"),
        FeedbackReasonOption(code: "unclear_text", localizationKey: "analysis.result_hub.feedback.reason.unclear_text"),
    ]

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isSubmitting else { return }
                    onClose()
                }

            VStack(spacing: 0) {
                header
                reasonGrid
                    .padding(.top, 14)

                if isComposerExpanded {
                    noteComposer
                        .padding(.top, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    customReasonButton
                        .padding(.top, 12)
                }

                if showsError {
                    Text(copy("analysis.result_hub.v2.gonderilemedi.lutfen.tekrar.deneyin.d5c399b5", "Gönderilemedi. Lütfen tekrar deneyin.", "Couldn't send. Please try again."))
                        .font(RDTypography.font(10.5, .semibold))
                        .foregroundStyle(Color(hex: "#B42318"))
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .background(Color.rdResultElevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: Color.black.opacity(0.18), radius: 22, x: 0, y: 12)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feedback.sheet")
        }
        .animation(.easeInOut(duration: 0.22), value: isComposerExpanded)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy("analysis.result_hub.v2.neyi.gelistirebiliriz.53de16e6", "NEYİ GELİŞTİREBİLİRİZ?", "WHAT CAN WE IMPROVE?"))
                    .font(RDTypography.font(17, .black))
                    .tracking(0.15)
                    .foregroundStyle(ink)

                Text(copy("analysis.result_hub.v2.gelismemize.yard.mc.ol.boylelikle.bir.sonr.9f8f2880", "Gelişmemize yardımcı ol, böylelikle bir sonraki analizinde mükemmele biraz daha yaklaşabilelim. Teşekkürler.", "Help us improve so your next analysis can get a little closer to perfect. Thank you."))
                .font(RDTypography.font(11.5, .medium))
                .foregroundStyle(muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(RDTypography.font(size: 12, weight: .black))
                    .foregroundStyle(Color.rdResultSecondaryText)
                    .frame(width: 30, height: 30)
                    .background(Color.rdResultSubtleSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy("analysis.result_hub.v2.kapat.3ad24beb", "Kapat", "Close"))
            .accessibilityIdentifier("feedback.close")
        }
    }

    private var reasonGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(reasons) { reason in
                Button {
                    submit(reason: reason.code, note: nil)
                } label: {
                    Text(RDLocalization.string(reason.localizationKey, table: .analysis, fallback: reason.code, language: language))
                        .font(RDTypography.font(11.5, .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 8)
                        .background(Color.rdResultSubtleSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(Color.rdResultLine, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(RDPressableButtonStyle())
                .disabled(isSubmitting)
                .accessibilityIdentifier("feedback.reason.\(reason.code)")
            }
        }
    }

    private var customReasonButton: some View {
        Button {
            showsError = false
            withAnimation(.easeInOut(duration: 0.22)) {
                isComposerExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                noteFocused = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(RDTypography.font(size: 13, weight: .semibold))
                Text(copy("analysis.result_hub.v2.nedenini.yazmak.istiyorum.76bf7572", "Nedenini Yazmak İstiyorum", "I want to explain why"))
                    .font(RDTypography.font(12, .heavy))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(RDTypography.font(size: 10, weight: .black))
            }
            .foregroundStyle(greenDark)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(Color.rdResultGreenTint)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(green.opacity(0.46), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityIdentifier("feedback.custom.toggle")
    }

    private var noteComposer: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text(copy("analysis.result_hub.v2.geri.bildiriminizi.yaz.n.86c7665a", "Geri bildiriminizi yazın...", "Write your feedback..."))
                        .font(RDTypography.font(11.5, .regular))
                        .foregroundStyle(Color.rdResultTertiaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $note)
                    .font(RDTypography.font(12, .regular))
                    .foregroundStyle(ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .focused($noteFocused)
                    .accessibilityLabel(copy("analysis.result_hub.v2.geri.bildiriminiz.7698d8e8", "Geri bildiriminiz", "Your feedback"))
                    .accessibilityIdentifier("feedback.custom.note")
            }
            .frame(height: 84)
            .background(Color.rdResultSubtleSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(noteFocused ? green.opacity(0.72) : Color.rdResultLine, lineWidth: 1.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Text("\(note.count)/1000")
                    .font(RDTypography.font(9.5, .medium))
                    .foregroundStyle(Color.rdResultTertiaryText)
                Spacer()
            }

            Button {
                submit(reason: "other", note: trimmedNote)
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(RDTypography.font(size: 13, weight: .semibold))
                    }
                    Text(copy("analysis.result_hub.v2.gonder.39122e84", "Gönder", "Send"))
                        .font(RDTypography.font(13.5, .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(trimmedNote.isEmpty ? Color(hex: "#8A8A8A") : Color(hex: "#111111"))
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(RDPressableButtonStyle())
            .disabled(trimmedNote.isEmpty || isSubmitting)
            .accessibilityIdentifier("feedback.custom.submit")
        }
        .onChange(of: note) { value in
            if value.count > 1000 { note = String(value.prefix(1000)) }
        }
    }

    private func submit(reason: String?, note: String?) {
        guard !isSubmitting else { return }
        showsError = false
        isSubmitting = true
        Task { @MainActor in
            let succeeded = await onSubmit(reason, note)
            isSubmitting = false
            if succeeded { onClose() }
            else { showsError = true }
        }
    }

    private func copy(_ key: String, _ turkish: String, _ english: String) -> String {
        RDLocalization.string(key, table: .analysis, fallback: language == .turkish ? turkish : english, language: language)
    }
}

struct FeedbackThanksToast: View {
    let language: RDLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(RDTypography.font(size: 11, weight: .black))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(Color.rdResultGreen)
                .clipShape(Circle())

            Text(RDLocalization.string(
                "analysis.result_hub.feedback.thanks",
                table: .analysis,
                fallback: language == .turkish
                    ? "Teşekkürler! Geri bildiriminizi en kısa sürede inceleyeceğiz."
                    : "Thank you! We'll review your feedback as soon as possible.",
                language: language
            ))
                .font(RDTypography.font(11.5, .semibold))
                .foregroundStyle(Color.rdResultPrimaryText)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: 340, alignment: .leading)
        .background(Color.rdResultElevatedSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdResultLine, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedback.success.toast")
        .allowsHitTesting(false)
    }
}

// MARK: Report sheet

private enum ReferenceReportSheetLayout {
    static let compactHeight: CGFloat = 364
    static let nonRiskHeight: CGFloat = 338
    static let initialHeight = compactHeight
    static let compactDetent: PresentationDetent = .height(compactHeight)
    static let nonRiskDetent: PresentationDetent = .height(nonRiskHeight)

    static func initialHeight(for section: AnalysisResultSectionID) -> CGFloat {
        section == .riskAnalysis ? compactHeight : nonRiskHeight
    }

    @MainActor
    static func fittedHeight(for measuredContentHeight: CGFloat) -> CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \UIWindow.isKeyWindow)
        let screenHeight = window?.bounds.height ?? UIScreen.main.bounds.height
        let topInset = window?.safeAreaInsets.top ?? 47
        let bottomInset = window?.safeAreaInsets.bottom ?? 34

        // A custom detent excludes the system bottom safe-area. The sheet itself
        // draws through that area, so subtract it once and retain a small optical
        // buffer for shadows and fractional layout rounding.
        let requested = ceil(measuredContentHeight - bottomInset + 12)
        let maximum = screenHeight - topInset - bottomInset - 12
        return min(maximum, max(compactHeight, requested))
    }
}

private enum ReferenceReportSheetMeasuredRegion: Hashable {
    case header
    case content
    case footer
}

private struct ReferenceReportSheetRegionHeightKey: PreferenceKey {
    static var defaultValue: [ReferenceReportSheetMeasuredRegion: CGFloat] = [:]

    static func reduce(
        value: inout [ReferenceReportSheetMeasuredRegion: CGFloat],
        nextValue: () -> [ReferenceReportSheetMeasuredRegion: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func reportSheetMeasuredHeight(_ region: ReferenceReportSheetMeasuredRegion) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReferenceReportSheetRegionHeightKey.self,
                    value: [region: proxy.size.height]
                )
            }
        }
    }
}

private struct ReferenceReportSheet: View {
    let section: AnalysisResultSectionID
    let language: RDLanguage
    let selectedCount: Int
    let totalCount: Int
    let isFreeTier: Bool
    let accessTier: SubscriptionTier
    let canReport: Bool
    let freeRiskAnalysisTrialRemaining: Int
    @Binding var method: RiskMethod
    @Binding var selectedCompany: Company?
    @Binding var reportKind: AnalysisResultHubReportKind?
    @Binding var reportFormat: String
    @Binding var preferredHeight: CGFloat
    @Binding var selectedDetent: PresentationDetent
    let onClose: () -> Void
    let onUpgrade: () -> Void
    let onGenerate: () -> Void

    @State private var companyPickerPresented = false
    @State private var companyCreatorPresented = false

    private let green = Color.rdResultGreen
    private let greenDark = Color.rdResultGreenDark
    private var isRisk: Bool { section == .riskAnalysis }
    private var hasRiskTableGift: Bool {
        isFreeTier && freeRiskAnalysisTrialRemaining > 0
    }
    private var canUseRiskTable: Bool {
        canReport && (!isFreeTier || hasRiskTableGift)
    }
    private var isGiftSelected: Bool {
        hasRiskTableGift && reportKind == .riskTable
    }
    private var canGenerate: Bool {
        guard canReport, selectedCount > 0 else { return false }
        guard isRisk else { return true }
        guard let reportKind else { return false }
        return reportKind != .riskTable || canUseRiskTable
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule().fill(Color.rdResultLine).frame(width: 42, height: 5).padding(.top, 10)
                HStack(spacing: 13) {
                    Image(systemName: "square.and.arrow.up")
                        .font(RDTypography.font(size: 21, weight: .semibold)).foregroundStyle(.white).frame(width: 46, height: 46)
                        .background(LinearGradient(colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color(hex: "#1F8F9C").opacity(0.26), radius: 6, y: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 0) {
                            Text(copy("analysis.result_hub.v2.raporunu.olustur.ve.3f14b005", "Raporunu oluştur ve ", "Create and "))
                                .foregroundStyle(Color.rdResultPrimaryText)
                            Text(copy("analysis.result_hub.v2.paylas.5ce2681b", "paylaş", "share your report"))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#E8762A"), Color(hex: "#1F8F9C")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .font(RDTypography.font(16.5, .black))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(copy("analysis.result_hub.v2.raporunu.olustur.ve.paylas.eba53443", "Raporunu oluştur ve paylaş", "Create and share your report"))
                        Text("\(selectedCount)/\(totalCount) \(selectedItemLabel) · PDF \(copy("analysis.result_hub.v2.veya.46b453c4", "veya", "or")) Excel")
                            .font(RDTypography.font(11, .semibold)).foregroundStyle(Color.rdResultTertiaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(RDTypography.font(size: 14, weight: .bold)).foregroundStyle(Color.rdResultSecondaryText)
                            .frame(width: 40, height: 40).background(Color.rdResultSubtleSurface).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 11)
            }
            .reportSheetMeasuredHeight(.header)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if isRisk {
                        reportTypeCard(
                            kind: .standard,
                            title: copy("analysis.result_hub.v2.standart.rapor.13083cc0", "Standart Rapor", "Standard Report"),
                            subtitle: copy("analysis.result_hub.v2.secili.bulgular.n.ozet.dokumu.9cda55fa", "Seçili bulguların özet dökümü", "Summary of selected findings"),
                            icon: "doc.text"
                        )
                        reportTypeCard(
                            kind: .riskTable,
                            title: copy("analysis.result_hub.v2.risk.analizi.tablosu.6ebbed72", "Risk Analizi Tablosu", "Risk Analysis Table"),
                            subtitle: copy("analysis.result_hub.v2.analizlerini.fine.kinney.veya.5.5.matris.i.4767b740", "Analizlerini Fine-Kinney veya 5×5 Matris ile hesapla, PDF ya da Excel olarak rapor oluştur ve paylaş.", "Calculate with Fine-Kinney or 5×5 Matrix, then create and share a PDF or Excel report."),
                            icon: "tablecells",
                            emphasized: true
                        )
                        if reportKind == .riskTable {
                            companySelection
                            fieldTitle(copy("analysis.result_hub.v2.yontem.8e151e54", "YÖNTEM", "METHOD")); segmentedMethod
                            fieldTitle(copy("analysis.result_hub.v2.cikti.bicimi.59bad551", "ÇIKTI BİÇİMİ", "OUTPUT FORMAT")); segmentedFormat
                        }
                        if isFreeTier && !canReport { upgradeCard }
                    } else {
                        fieldTitle(copy("analysis.result_hub.v2.cikti.bicimi.secin.958da115", "ÇIKTI BİÇİMİ SEÇİN", "SELECT OUTPUT FORMAT"))
                        formatCard("pdf", title: copy("analysis.result_hub.v2.pdf.olarak.indir.07a7e79b", "PDF olarak indir", "Download as PDF"), subtitle: copy("analysis.result_hub.v2.bask.ya.ve.paylas.ma.haz.r.duzen.096236fc", "Baskıya ve paylaşıma hazır düzen", "Print-ready and shareable layout"))
                        formatCard("xlsx", title: copy("analysis.result_hub.v2.excel.olarak.indir.72738cce", "Excel olarak indir", "Download as Excel"), subtitle: copy("analysis.result_hub.v2.duzenlenebilir.tablo.filtreli.sutunlar.1e727e15", "Düzenlenebilir tablo, filtreli sütunlar", "Editable table with filtered columns"))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                .reportSheetMeasuredHeight(.content)
            }
            Button {
                if canGenerate { onGenerate() } else if !canReport { onUpgrade() }
            } label: {
                HStack(spacing: 9) { Image(systemName: canReport ? "arrow.down.to.line" : "lock.fill"); Text(generateTitle) }
                    .font(RDTypography.font(15.5, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(canGenerate ? Color(hex: "#111111") : (canReport ? Color(hex: "#D8D8D8") : greenDark))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: canGenerate ? Color.black.opacity(0.28) : .clear, radius: 8, x: 4, y: 7)
            }
            .buttonStyle(.plain).disabled(!canGenerate && canReport)
            .accessibilityIdentifier("result.report_sheet.generate")
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 24)
            .background(Color.rdResultElevatedSurface.shadow(.drop(color: Color.black.opacity(0.20), radius: 9, y: -6)))
            .reportSheetMeasuredHeight(.footer)
        }
        .background(Color.rdResultBackground)
        // A fixed-height sheet normally reserves another content inset above its
        // own home-indicator area. Drawing the surface through that inset removes
        // the apparent second footer while UIKit still keeps the gesture region.
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityIdentifier("result.report_sheet")
        .onPreferenceChange(ReferenceReportSheetRegionHeightKey.self) { heights in
            updatePreferredHeight(using: heights)
        }
        .sheet(isPresented: $companyPickerPresented) {
            ReferenceCompanyPickerSheet(
                language: language,
                selectedCompany: $selectedCompany
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $companyCreatorPresented) {
            CompanyPickerSheet(
                title: copy("analysis.result_hub.v2.firma.ekle.703fd054", "Firma ekle", "Add company"),
                accessTier: accessTier,
                selectedCompanyID: selectedCompany?.id,
                allowNoCompany: true,
                startsInCreateMode: true,
                onSelect: { company in
                    selectedCompany = company
                },
                onPaywall: onUpgrade
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func updatePreferredHeight(
        using heights: [ReferenceReportSheetMeasuredRegion: CGFloat]
    ) {
        guard isRisk else { return }
        guard let headerHeight = heights[.header],
              let contentHeight = heights[.content],
              let footerHeight = heights[.footer],
              headerHeight > 0,
              contentHeight > 0,
              footerHeight > 0 else { return }

        let fittedHeight = ReferenceReportSheetLayout.fittedHeight(
            for: headerHeight + contentHeight + footerHeight
        )
        guard abs(fittedHeight - preferredHeight) > 1 else { return }

        // Preference callbacks occur during layout. Defer the detent mutation to
        // the next main-loop turn so the new height and selected detent become
        // valid in the same presentation update without a UIKit fallback jump.
        DispatchQueue.main.async {
            preferredHeight = fittedHeight
            selectedDetent = .height(fittedHeight)
        }
    }

    @ViewBuilder
    private var companySelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isFreeTier {
                fieldTitle(copy("analysis.result_hub.v2.firma.90198323", "FİRMA", "COMPANY"))
                Button(action: onUpgrade) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(RDTypography.font(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#A99A6D"))
                            .frame(width: 30, height: 30)
                            .background(Color.rdResultKhakiTint)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(copy("analysis.result_hub.v2.firma.secimi.kilitli.adf418a9", "Firma seçimi kilitli", "Company selection is locked"))
                                .font(RDTypography.font(12.5, .heavy))
                                .foregroundStyle(Color.rdResultSecondaryText)
                            Text(copy("analysis.result_hub.v2.rapor.kendi.firmana.gore.uretilir.f9202ded", "Rapor kendi firmana göre üretilir", "Generate reports for your company"))
                                .font(RDTypography.font(10, .semibold))
                                .foregroundStyle(Color.rdResultTertiaryText)
                        }
                        Spacer(minLength: 8)
                        Text("PLUS / PRO")
                            .font(RDTypography.font(8, .black))
                            .foregroundStyle(Color.rdResultPrimaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.rdResultElevatedSurface)
                            .overlay {
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(hex: "#D9A91A"), Color(hex: "#008FA0")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 48)
                    .background(Color.rdResultSubtleSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(
                                Color.rdResultLine,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("result.report_sheet.company.locked")
            } else {
                HStack {
                    fieldTitle(copy("analysis.result_hub.v2.firma.90198323", "FİRMA", "COMPANY"))
                    Spacer()
                    Button {
                        companyCreatorPresented = true
                    } label: {
                        Text(copy("analysis.result_hub.v2.firma.ekle.703fd054", "Firma ekle", "Add company"))
                            .font(RDTypography.font(9.5, .heavy))
                            .foregroundStyle(greenDark)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    companyPickerPresented = true
                } label: {
                    HStack(spacing: 10) {
                        companyAvatar(selectedCompany)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedCompany?.name ?? copy("analysis.result_hub.v2.firma.sec.ae50b7a6", "Firma seç", "Select company"))
                                .font(RDTypography.font(12.5, .heavy))
                                .foregroundStyle(Color.rdResultPrimaryText)
                                .lineLimit(1)
                            Text(companySubtitle(selectedCompany))
                                .font(RDTypography.font(9.5, .medium))
                                .foregroundStyle(Color.rdResultTertiaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(RDTypography.font(size: 13, weight: .bold))
                            .foregroundStyle(Color.rdResultTertiaryText)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 48)
                    .background(Color.rdResultSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(green.opacity(0.38), lineWidth: 1.2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("result.report_sheet.company.select")
            }
        }
    }

    @ViewBuilder
    private func companyAvatar(_ company: Company?) -> some View {
        if let company {
            Text(companyInitials(company.name))
                .font(RDTypography.font(9.5, .black))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(green)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        } else {
            Image(systemName: "building.2")
                .font(RDTypography.font(size: 14, weight: .semibold))
                .foregroundStyle(greenDark)
                .frame(width: 32, height: 32)
                .background(Color.rdResultGreenTint)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private func companySubtitle(_ company: Company?) -> String {
        guard let company else {
            return copy("analysis.result_hub.v2.rapor.icin.firma.secin.f925120d", "Rapor için firma seçin", "Choose a company for this report")
        }
        let subtitle = company.listSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return subtitle.isEmpty
            ? copy("analysis.result_hub.v2.rapor.icin.secildi.f4b0b22b", "Rapor için seçildi", "Selected for this report")
            : subtitle
    }

    private func companyInitials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let initials = words.compactMap(\.first).map(String.init).joined()
        return initials.uppercased(with: Locale(identifier: language == .turkish ? "tr_TR" : "en_US"))
    }

    private func reportTypeCard(
        kind: AnalysisResultHubReportKind,
        title: String,
        subtitle: String,
        icon: String,
        emphasized: Bool = false
    ) -> some View {
        let selected = reportKind == kind
        let gifted = kind == .riskTable && hasRiskTableGift
        return Button {
            if kind == .riskTable && !canUseRiskTable {
                onUpgrade()
            } else {
                reportKind = kind
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                reportTypeIcon(icon, selected: selected, emphasized: emphasized, gifted: gifted)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(RDTypography.font(14.5, .heavy))
                        .foregroundStyle(Color.rdResultPrimaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                        .accessibilityIdentifier("result.report_sheet.option.\(kind.rawValue).title")
                    if gifted { riskTableGiftBadge }
                    if gifted {
                        Text(copy("analysis.result_hub.v2.uyeligine.ozel.1.kerelik.olusturma.hakk.n..f00bf147", "Üyeliğine özel: 1 kerelik oluşturma hakkın tanımlandı", "Membership gift: your one-time report credit is ready"))
                        .font(RDTypography.font(10, .bold))
                        .foregroundStyle(Color(hex: "#B47C00"))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    reportTypeSubtitle(subtitle, emphasized: emphasized)
                        .font(RDTypography.font(11.5, .medium))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(); radio(selected)
            }
            .padding(.horizontal, 15).padding(.vertical, emphasized ? 16 : 13)
            .frame(minHeight: emphasized ? (gifted ? 142 : 120) : 78, alignment: .top)
            .background(selected ? Color.rdResultSelectedSurface : (gifted ? Color.rdResultAmberTint : Color.rdResultSurface))
            .overlay {
                if gifted {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(selected ? green : Color(hex: "#E4C66D"), lineWidth: selected ? 2.4 : 1.4)
                } else if emphasized {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#E8762A"), Color(hex: "#E0A828"), Color(hex: "#4FAE7A"), Color(hex: "#1F8F9C")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: selected ? 2.4 : 1.8
                        )
                } else {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(selected ? green : Color.rdResultLine, lineWidth: selected ? 1.8 : 1.2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("result.report_sheet.option.\(kind.rawValue)")
    }

    private var riskTableGiftBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "gift.fill")
                .font(RDTypography.font(size: 8, weight: .bold))
            Text(copy("analysis.result_hub.v2.1.hak.hediye.6db763f3", "1 HAK HEDİYE", "1 FREE CREDIT"))
                .font(RDTypography.font(8, .black))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(hex: "#E6A52A"), Color(hex: "#4EAF7A")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .fixedSize()
        .accessibilityLabel(copy("analysis.result_hub.v2.bir.hak.hediye.1ffce326", "Bir hak hediye", "One free credit"))
        .accessibilityIdentifier("result.report_sheet.option.riskTable.gift")
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
            return Text(copy("analysis.result_hub.v2.analizlerini.7d5e7559", "Analizlerini ", "Calculate with "))
                + Text("Fine-Kinney").underline()
                + Text(copy("analysis.result_hub.v2.veya.5e79def6", " veya ", " or "))
                + Text("5×5 Matris").underline()
                + Text(copy("analysis.result_hub.v2.ile.hesapla.5912929a", " ile hesapla, ", ", then create and share a "))
                + Text("PDF").underline()
                + Text(copy("analysis.result_hub.v2.ya.da.40287c6c", " ya da ", " or "))
                + Text("Excel").underline()
                + Text(copy("analysis.result_hub.v2.olarak.rapor.olustur.ve.paylas.00a71509", " olarak rapor oluştur ve paylaş.", " report."))
        }
        return Text(copy("analysis.result_hub.v2.analizlerini.7d5e7559", "Analizlerini ", "Calculate with "))
            + Text("Fine-Kinney").underline()
            + Text(copy("analysis.result_hub.v2.veya.5e79def6", " veya ", " or "))
            + Text("5×5 Matrix").underline()
            + Text(copy("analysis.result_hub.v2.ile.hesapla.5912929a", " ile hesapla, ", ", then create and share a "))
            + Text("PDF").underline()
            + Text(copy("analysis.result_hub.v2.ya.da.40287c6c", " ya da ", " or "))
            + Text("Excel").underline()
            + Text(copy("analysis.result_hub.v2.olarak.rapor.olustur.ve.paylas.00a71509", " olarak rapor oluştur ve paylaş.", " report."))
    }

    @ViewBuilder
    private func reportTypeIcon(_ icon: String, selected: Bool, emphasized: Bool, gifted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        if gifted {
            Image(systemName: icon)
                .font(RDTypography.font(size: 23, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color(hex: "#A87900"))
                .frame(width: 48, height: 48)
                .background(selected ? green : Color(hex: "#F8EFCF"))
                .clipShape(shape)
        } else if emphasized {
            Image(systemName: icon)
                .font(RDTypography.font(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
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
                .font(RDTypography.font(size: 22, weight: .regular))
                .foregroundStyle(selected ? .white : Color.rdResultSecondaryText)
                .frame(width: 46, height: 46)
                .background(selected ? green : Color.rdResultSubtleSurface)
                .clipShape(shape)
        }
    }

    private func formatCard(_ format: String, title: String, subtitle: String) -> some View {
        let selected = reportFormat == format
        let pdf = format == "pdf"
        return Button { reportFormat = format } label: {
            HStack(spacing: 10) {
                Text(pdf ? "PDF" : "XLS").font(RDTypography.font(10, .black))
                    .foregroundStyle(pdf ? Color(hex: "#C9352B") : greenDark).frame(width: 36, height: 36)
                    .background(pdf ? Color.rdCriticalBg : Color.rdResultGreenTint).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(RDTypography.font(14, .heavy))
                        .foregroundStyle(selected ? greenDark : Color.rdResultPrimaryText)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(RDTypography.font(11, .medium))
                        .foregroundStyle(Color.rdResultTertiaryText)
                        .lineLimit(2)
                }
                Spacer(); radio(selected)
            }
            .padding(11).background(selected ? Color.rdResultSelectedSurface : Color.rdResultSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? green : Color.rdResultLine, lineWidth: selected ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var segmentedMethod: some View {
        HStack(spacing: 3) {
            segment("Fine-Kinney", subtitle: localizedRiskFormula(.fineKinney), selected: method == .fineKinney) { method = .fineKinney }
            segment(copy("analysis.result_hub.v2.5.5.matris.30882165", "5×5 Matris", "5×5 Matrix"), subtitle: localizedRiskFormula(.matrix5x5), selected: method == .matrix5x5) { method = .matrix5x5 }
        }
        .padding(4).background(Color.rdResultSubtleSurface).clipShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityIdentifier("result.report_sheet.method")
    }

    private var segmentedFormat: some View {
        HStack(spacing: 3) {
            segment("PDF", subtitle: copy("analysis.result_hub.v2.bask.ya.haz.r.981e1308", "Baskıya hazır", "Print ready"), selected: reportFormat == "pdf") { reportFormat = "pdf" }
            segment("Excel", subtitle: copy("analysis.result_hub.v2.duzenlenebilir.adecc32b", "Düzenlenebilir", "Editable"), selected: reportFormat == "xlsx") { reportFormat = "xlsx" }
        }
        .padding(4).background(Color.rdResultSubtleSurface).clipShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityIdentifier("result.report_sheet.format")
    }

    private func segment(_ title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.rdResultElevatedSurface)
                        .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                }
                VStack(spacing: 2) {
                    Text(title).font(RDTypography.font(11.5, .heavy))
                    Text(subtitle).font(RDTypography.font(9, .semibold))
                }
                .foregroundStyle(selected ? greenDark : Color.rdResultSecondaryText)
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
                    .background(Color.rdResultKhakiTint).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy("analysis.result_hub.v2.plus.veya.pro.ile.ac.feb08372", "PLUS veya PRO ile aç", "Unlock with PLUS or PRO")).font(RDTypography.font(12.5, .heavy))
                    Text(copy("analysis.result_hub.v2.rapor.haklar.ve.excel.c.kt.s.55eb6d2d", "Rapor hakları ve Excel çıktısı", "Report access and Excel export"))
                        .font(RDTypography.font(10, .semibold)).foregroundStyle(Color.rdResultTertiaryText)
                }
                Spacer()
                Text("PLUS / PRO").font(RDTypography.font(8, .black)).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.rdResultElevatedSurface).clipShape(Capsule())
            }
            .foregroundStyle(Color.rdResultSecondaryText).padding(10).background(Color.rdResultSubtleSurface)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.rdResultLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func radio(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark" : "").font(RDTypography.font(size: 11, weight: .black)).foregroundStyle(.white)
            .frame(width: 26, height: 26).background(selected ? green : Color.rdResultSurface)
            .overlay(Circle().stroke(selected ? green : Color.rdResultLine, lineWidth: 1.5)).clipShape(Circle())
    }
    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(RDTypography.font(9, .heavy)).tracking(0.6).foregroundStyle(Color.rdResultTertiaryText)
    }
    private var generateTitle: String {
        if !canReport { return copy("analysis.result_hub.v2.plus.pro.ile.ac.9ed9163b", "PLUS / PRO ile aç", "Unlock with PLUS / PRO") }
        if isGiftSelected { return copy("analysis.result_hub.v2.hediye.hakk.mla.olustur.df5fb619", "Hediye hakkımla oluştur", "Create with my free credit") }
        guard canGenerate else { return copy("analysis.result_hub.v2.rapor.turu.secin.49b32bcb", "Rapor türü seçin", "Select report type") }
        if reportKind == .standard { return copy("analysis.result_hub.v2.standart.rapor.olustur.6e694f0f", "Standart Rapor Oluştur", "Create Standard Report") }
        return reportFormat == "xlsx" ? copy("analysis.result_hub.v2.excel.raporu.olustur.66221b45", "Excel Raporu Oluştur", "Create Excel Report") : copy("analysis.result_hub.v2.pdf.raporu.olustur.891e596f", "PDF Raporu Oluştur", "Create PDF Report")
    }
    private var selectedItemLabel: String {
        selectedCount == 1 ? copy("analysis.result_hub.v2.kay.t.secili.a5f9a55c", "kayıt seçili", "item selected") : copy("analysis.result_hub.v2.kay.t.secili.880c1368", "kayıt seçili", "items selected")
    }
    private func localizedRiskFormula(_ method: RiskMethod) -> String {
        switch method {
        case .fineKinney:
            return RDLocalization.string(
                "analysis.finding.o.f.s.1a128241",
                table: .analysis,
                fallback: "O × F × Ş",
                language: language
            )
        case .matrix5x5:
            return RDLocalization.string(
                "analysis.finding.o.s.e9e53958",
                table: .analysis,
                fallback: "O × Ş",
                language: language
            )
        }
    }
    private func copy(_ key: String, _ tr: String, _ en: String) -> String {
        RDLocalization.string(key, table: .analysis, fallback: language == .turkish ? tr : en, language: language)
    }
}

private struct ReferenceCompanyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let language: RDLanguage
    @Binding var selectedCompany: Company?

    @State private var companies: [Company] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let green = Color.rdResultGreen
    private let greenDark = Color.rdResultGreenDark

    private var filteredCompanies: [Company] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return companies }
        return companies.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.listSubtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(copy("analysis.result_hub.v2.firma.sec.ae50b7a6", "Firma seç", "Select company"))
                    .font(RDTypography.font(17, .black))
                    .foregroundStyle(Color.rdResultPrimaryText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(RDTypography.font(size: 14, weight: .bold))
                        .foregroundStyle(Color.rdResultSecondaryText)
                        .frame(width: 40, height: 40)
                        .background(Color.rdResultSubtleSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy("analysis.result_hub.v2.kapat.3ad24beb", "Kapat", "Close"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(RDTypography.font(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rdResultTertiaryText)
                TextField(copy("analysis.result_hub.v2.firma.ad.veya.sektor.ara.9270211a", "Firma adı veya sektör ara", "Search company or sector"), text: $searchText)
                    .font(RDTypography.font(13.5, .medium))
                    .foregroundStyle(Color.rdResultPrimaryText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 13)
            .frame(height: 50)
            .background(Color.rdResultSubtleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .accessibilityIdentifier("result.company_picker.search")

            HStack(spacing: 10) {
                Text("\(filteredCompanies.count) \(filteredCompanies.count == 1 ? copy("analysis.result_hub.v2.firma.90198323", "FİRMA", "COMPANY") : copy("analysis.result_hub.v2.firma.4beb43de", "FİRMA", "COMPANIES"))")
                    .font(RDTypography.font(9.5, .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.rdResultTertiaryText)
                Rectangle()
                    .fill(Color.rdResultLine)
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Group {
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView().tint(green)
                        Text(copy("analysis.result_hub.v2.firmalar.yukleniyor.27f1de9c", "Firmalar yükleniyor", "Loading companies"))
                            .font(RDTypography.font(11, .semibold))
                            .foregroundStyle(Color.rdResultSecondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(RDTypography.font(11, .medium))
                            .foregroundStyle(Color.rdResultSecondaryText)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await loadCompanies() }
                        } label: {
                            Label(copy("analysis.result_hub.v2.tekrar.dene.bb3d56af", "Tekrar dene", "Try again"), systemImage: "arrow.clockwise")
                                .font(RDTypography.font(11, .heavy))
                                .foregroundStyle(greenDark)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredCompanies.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "building.2")
                            .font(RDTypography.font(size: 24, weight: .semibold))
                            .foregroundStyle(Color.rdResultTertiaryText)
                        Text(searchText.isEmpty
                             ? copy("analysis.result_hub.v2.kay.tl.firma.bulunmuyor.ab9c253c", "Kayıtlı firma bulunmuyor", "No saved companies")
                             : copy("analysis.result_hub.v2.araman.zla.eslesen.firma.yok.9e628b24", "Aramanızla eşleşen firma yok", "No companies match your search"))
                            .font(RDTypography.font(12, .semibold))
                            .foregroundStyle(Color.rdResultSecondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredCompanies) { company in
                                companyRow(company)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.rdResultBackground.ignoresSafeArea())
        .task { await loadCompanies() }
        .accessibilityIdentifier("result.company_picker")
    }

    private func companyRow(_ company: Company) -> some View {
        let selected = selectedCompany?.id == company.id
        return Button {
            selectedCompany = company
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(initials(company.name))
                    .font(RDTypography.font(9.5, .black))
                    .foregroundStyle(selected ? Color.white : Color.rdResultSecondaryText)
                    .frame(width: 36, height: 36)
                    .background(selected ? green : Color.rdResultSubtleSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name)
                        .font(RDTypography.font(13, selected ? .heavy : .semibold))
                        .foregroundStyle(selected ? greenDark : Color.rdResultPrimaryText)
                        .lineLimit(1)
                    Text(company.listSubtitle.isEmpty
                         ? copy("analysis.result_hub.v2.firma.kayd.e73624c2", "Firma kaydı", "Company record")
                         : company.listSubtitle)
                        .font(RDTypography.font(10, .medium))
                        .foregroundStyle(Color.rdResultTertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark" : "")
                    .font(RDTypography.font(size: 11, weight: .black))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(selected ? green : Color.rdResultSurface)
                    .overlay {
                        Circle().stroke(selected ? green : Color.rdResultLine, lineWidth: 1.5)
                    }
                    .clipShape(Circle())
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 56)
            .background(selected ? Color.rdResultSelectedSurface : Color.rdResultSurface)
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(company.name)
        .accessibilityValue(selected ? copy("analysis.result_hub.v2.secili.9fce9c94", "Seçili", "Selected") : copy("analysis.result_hub.v2.secili.degil.fe86ff2a", "Seçili değil", "Not selected"))
        .accessibilityIdentifier("result.company_picker.company.\(company.id.uuidString)")
    }

    private func loadCompanies() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            companies = try await CompanyService.shared.listCompanies()
        } catch {
            companies = []
            errorMessage = error.localizedDescription
        }
    }

    private func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.uppercased(with: Locale(identifier: language == .turkish ? "tr_TR" : "en_US"))
    }

    private func copy(_ key: String, _ tr: String, _ en: String) -> String {
        RDLocalization.string(key, table: .analysis, fallback: language == .turkish ? tr : en, language: language)
    }
}

// MARK: Expert / notebook detail sheet

private struct ReferenceHubDetailView: View {
    let item: AnalysisResultHubItem
    let section: AnalysisResultSectionID
    let language: RDLanguage
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let green = Color.rdResultGreen

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").font(RDTypography.font(size: 17, weight: .semibold)).frame(width: 36, height: 36)
                        .background(Color.rdResultSubtleSurface).clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(section.title(language: language)).font(RDTypography.font(15, .heavy))
                Spacer()
                Menu {
                    Button(action: onEdit) { Label(copy("analysis.result_hub.v2.duzenle.3248ed57", "Düzenle", "Edit"), systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) { Label(copy("analysis.result_hub.v2.sil.c0b0d3c6", "Sil", "Delete"), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(RDTypography.font(size: 17, weight: .semibold)).frame(width: 36, height: 36)
                        .background(Color.rdResultSubtleSurface).clipShape(Circle())
                }
            }
            .foregroundStyle(Color.rdResultPrimaryText).padding(.horizontal, 18).padding(.vertical, 10)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.displayTitle(language: language)).font(RDTypography.font(22, .black)).foregroundStyle(Color.rdResultPrimaryText)
                    if !item.displayBody.isEmpty { detailBlock(copy("analysis.result_hub.v2.ac.klama.c96157c8", "Açıklama", "Description"), item.displayBody, color: Color.rdResultBlueTint) }
                    if let root = item.rootCauseText, !root.isEmpty { detailBlock(copy("analysis.result_hub.v2.kok.neden.a37f29be", "Kök Neden", "Root Cause"), root, color: Color.rdResultAmberTint) }
                    if let action = item.recommendedAction, !action.isEmpty { detailBlock(copy("analysis.result_hub.v2.oneri.cbecd1fc", "Öneri", "Recommendation"), action, color: Color.rdResultGreenTintStrong) }
                    if let finding = item.findingText, !finding.isEmpty { detailBlock(copy("analysis.result_hub.v2.tespit.4e395ed8", "Tespit", "Finding"), finding, color: Color.rdResultAmberTint) }
                    if let recommendation = item.recommendationText, !recommendation.isEmpty { detailBlock(copy("analysis.result_hub.v2.oneri.cbecd1fc", "Öneri", "Recommendation"), recommendation, color: Color.rdResultGreenTintStrong) }
                    if let reference = item.referenceText ?? item.referencesText, !reference.isEmpty { detailBlock(copy("analysis.result_hub.v2.dayanak.990d0beb", "Dayanak", "Basis"), reference, color: Color.rdResultBlueTint) }
                }
                .padding(20)
            }
        }
        .background(Color.rdResultBackground)
    }
    private func detailBlock(_ title: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased(with: language.locale))
                .font(RDTypography.font(10.5, .black))
                .tracking(0.6)
                .foregroundStyle(green)
            Text(text).font(RDTypography.font(13.5, .regular)).foregroundStyle(Color.rdResultSecondaryText)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading).background(color).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func copy(_ key: String, _ tr: String, _ en: String) -> String {
        RDLocalization.string(key, table: .analysis, fallback: language == .turkish ? tr : en, language: language)
    }
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
