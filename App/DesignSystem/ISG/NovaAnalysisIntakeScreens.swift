import SwiftUI

/// One company the expert can attach this analysis to.
struct NovaAnalysisCompanyOption: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: String
    /// The sector free text the company was saved with. Recognised values
    /// pre-select a sector; anything else leaves the choice to the expert.
    let sector: String?
}

struct NovaAnalysisSectorOption: Identifiable, Equatable {
    let id: String
    let label: String
    let subtitle: String
    let symbol: String
}

struct NovaAnalysisFocusOption: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// A focus the account's plan does not include. It is shown, never silently
    /// removed, and it cannot be selected.
    let isLocked: Bool
    let lockLabel: String
}

/// Company → sector → focus, asked in one centred popup once the photos are
/// already chosen. Every step can be revisited; nothing is decided unseen.
struct NovaAnalysisIntakePopup: View {
    let companies: [NovaAnalysisCompanyOption]
    let sectors: [NovaAnalysisSectorOption]
    let focuses: [NovaAnalysisFocusOption]
    @Binding var draft: NovaAnalysisIntakeDraft
    var isStarting = false
    let onStart: () -> Void
    @State private var step: NovaAnalysisIntakeStep = .owner
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme

    private var catalog: [NovaSectorCandidate] {
        sectors.map { .init(id: $0.id, labels: [$0.label]) }
    }
    private var matches: [NovaAnalysisCompanyOption] {
        let needle = NovaSectorMatch.normalize(query)
        guard !needle.isEmpty else { return companies }
        return companies.filter { NovaSectorMatch.normalize($0.name).contains(needle) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                steps
                switch step {
                case .owner: ownerStep
                case .sector: sectorStep
                case .focus: focusStep
                }
                footer
            }.padding(20).novaPopupContentSize()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if step != .owner {
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                }.buttonStyle(NovaRowPressStyle()).disabled(isStarting)
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri")))
                    .accessibilityIdentifier("analysis.intake.back")
            }
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: stepTitle, style: .sheetTitle)
                NovaText(text: String(format: RDLocalization.string("localizable.nova.intake.photo.count.short", table: .localizable,
                    fallback: "%d fotoğraf seçildi"), draft.photoCount), style: .metaQuiet)
            }
            Spacer(minLength: 0)
        }
    }

    private var stepTitle: String {
        switch step {
        case .owner: return RDLocalization.string("localizable.nova.intake.step.owner", table: .localizable, fallback: "Firma seçimi")
        case .sector: return RDLocalization.string("localizable.nova.intake.step.sector", table: .localizable, fallback: "Sektör seçimi")
        case .focus: return RDLocalization.string("localizable.nova.intake.step.focus", table: .localizable, fallback: "Analiz odağı")
        }
    }
    private var stepHint: String {
        switch step {
        case .owner: return RDLocalization.string("localizable.nova.intake.hint.owner", table: .localizable,
            fallback: "Analizi bir firmaya bağlayabilir ya da firmasız sürdürüp sonradan atayabilirsiniz.")
        case .sector: return RDLocalization.string("localizable.nova.intake.hint.sector", table: .localizable,
            fallback: "Risk öncelikleri ve öneriler seçtiğiniz sektöre göre uyarlanır.")
        case .focus: return RDLocalization.string("localizable.nova.intake.hint.focus", table: .localizable,
            fallback: "En az bir odak seçin. Odak sayısı analizin kapsamını belirler.")
        }
    }

    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(NovaAnalysisIntakeStep.allCases) { value in
                Capsule()
                    .fill(reached(value) ? NovaColorToken.accent.color(in: scheme)
                                         : NovaColorToken.borderMuted.color(in: scheme))
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: stepTitle))
    }
    private func reached(_ value: NovaAnalysisIntakeStep) -> Bool {
        guard let at = NovaAnalysisIntakeStep.allCases.firstIndex(of: value),
              let now = NovaAnalysisIntakeStep.allCases.firstIndex(of: step) else { return false }
        return at <= now
    }

    // MARK: company

    @ViewBuilder private var ownerStep: some View {
        NovaHelpHint(text: stepHint)
        if companies.count > 4 {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).accessibilityHidden(true)
                TextField(RDLocalization.string("localizable.nova.intake.owner.search", table: .localizable, fallback: "Firma ara"), text: $query)
                    .font(NovaFont.font(.body)).submitLabel(.done)
                    .accessibilityIdentifier("analysis.intake.owner.search")
            }.padding(.horizontal, 12).frame(minHeight: 42)
                .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
        }
        ownerRow(title: RDLocalization.string("localizable.nova.intake.owner.none", table: .localizable, fallback: "Firmasız devam et"),
                 detail: RDLocalization.string("localizable.nova.intake.owner.none.detail", table: .localizable,
                    fallback: "Analiz hesabınızda kalır; sonradan bir firmaya atayabilirsiniz."),
                 symbol: "person", isSelected: draft.owner == .unassigned,
                 identifier: "analysis.intake.owner.none") {
            draft.choose(owner: .unassigned, catalog: catalog)
        }
        if companies.isEmpty {
            NovaCard(padding: 14) {
                NovaText(text: RDLocalization.string("localizable.nova.intake.owner.empty", table: .localizable,
                    fallback: "Bu hesapta pilot firma yok. Firmasız devam edebilirsiniz."), style: .metaQuiet)
            }
        } else if matches.isEmpty {
            NovaCard(padding: 14) {
                NovaText(text: RDLocalization.string("localizable.nova.intake.owner.no.match", table: .localizable,
                    fallback: "Aramayla eşleşen firma yok."), style: .metaQuiet)
            }
        }
        ForEach(matches) { company in
            ownerRow(title: company.name, detail: companyDetail(company), symbol: "building.2",
                     isSelected: draft.owner.companyID == company.id,
                     identifier: "analysis.intake.owner.\(company.id.uuidString.lowercased())") {
                draft.choose(owner: .company(id: company.id, name: company.name, sector: company.sector), catalog: catalog)
            }
        }
    }

    /// The company row says whether its sector will pre-select one, so the note
    /// on the next step is never a surprise.
    private func companyDetail(_ company: NovaAnalysisCompanyOption) -> String {
        guard let sector = company.sector?.trimmingCharacters(in: .whitespacesAndNewlines), !sector.isEmpty
        else { return company.detail }
        let known = NovaSectorMatch.suggestion(for: sector, in: catalog) != nil
        let suffix = known ? "" : " · " + RDLocalization.string("localizable.nova.intake.owner.sector.unknown",
            table: .localizable, fallback: "sektör tanınmadı")
        return company.detail.isEmpty ? sector + suffix : company.detail + " · " + sector + suffix
    }

    private func ownerRow(title: String, detail: String, symbol: String, isSelected: Bool,
                          identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaCard(padding: 12, border: isSelected ? NovaColorToken.accentInk.color(in: scheme) : .clear) {
                HStack(spacing: 10) {
                    NovaIcon(symbol: symbol, size: 17)
                        .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: title, style: .cardTitle)
                        if !detail.isEmpty { NovaText(text: detail, style: .metaQuiet) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                                    : NovaColorToken.borderStrong.color(in: scheme))
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier(identifier)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: sector

    @ViewBuilder private var sectorStep: some View {
        NovaHelpHint(text: stepHint)
        // The note only stands while the pre-selection is still untouched.
        if draft.sectorCameFromCompany, let name = draft.owner.companyName {
            NovaCard(padding: 11, tint: NovaColorToken.statusInfoBg.color(in: scheme)) {
                HStack(alignment: .top, spacing: 8) {
                    NovaIcon(symbol: "sparkle", size: 14)
                        .foregroundStyle(NovaColorToken.statusInfoInk.color(in: scheme))
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.intake.sector.auto", table: .localizable,
                        fallback: "%@ firmasının sektörü otomatik seçildi. İsterseniz değiştirebilirsiniz."), name),
                        style: .metaQuiet, color: NovaColorToken.statusInfoInk.color(in: scheme))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("analysis.intake.sector.auto")
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2), spacing: 7) {
            ForEach(sectors) { sector in sectorChip(sector) }
        }
    }

    private func sectorChip(_ sector: NovaAnalysisSectorOption) -> some View {
        let isSelected = draft.sectorID == sector.id
        return Button { draft.choose(sector: sector.id) } label: {
            NovaCard(padding: 10, border: isSelected ? NovaColorToken.accentInk.color(in: scheme) : .clear,
                     tint: isSelected ? NovaColorToken.statusSuccessBg.color(in: scheme) : nil) {
                VStack(alignment: .leading, spacing: 4) {
                    NovaIcon(symbol: sector.symbol, size: 16)
                        .foregroundStyle(isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                                    : NovaColorToken.textSecondary.color(in: scheme))
                    NovaText(text: sector.label, style: .cardTitle)
                }.frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
            }
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("analysis.intake.sector.\(sector.id)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: focus

    @ViewBuilder private var focusStep: some View {
        NovaHelpHint(text: stepHint)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2), spacing: 7) {
            ForEach(focuses) { focus in focusRow(focus) }
        }
    }

    private func focusRow(_ focus: NovaAnalysisFocusOption) -> some View {
        let isSelected = draft.focusIDs.contains(focus.id)
        return Button {
            guard !focus.isLocked else { return }
            draft.toggle(focus: focus.id)
        } label: {
            NovaCard(padding: 10, border: isSelected ? NovaColorToken.accentInk.color(in: scheme) : .clear,
                     tint: isSelected ? NovaColorToken.statusSuccessBg.color(in: scheme) : nil) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        NovaIcon(symbol: focus.symbol, size: 16)
                            .foregroundStyle(isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                                        : NovaColorToken.textSecondary.color(in: scheme))
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(focus.isLocked ? NovaColorToken.borderStrong.color(in: scheme)
                                : isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                             : NovaColorToken.borderStrong.color(in: scheme))
                    }
                    HStack(spacing: 6) {
                        NovaText(text: focus.title, style: .cardTitle)
                        if focus.isLocked { NovaStatusPill(label: focus.lockLabel, status: .neutral, showsDot: false) }
                    }
                    NovaText(text: focus.detail, style: .metaQuiet).lineLimit(3)
                }.frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            }.opacity(focus.isLocked ? 0.55 : 1)
        }.buttonStyle(NovaRowPressStyle()).disabled(focus.isLocked)
            .accessibilityIdentifier("analysis.intake.focus.\(focus.id)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: footer

    @ViewBuilder private var footer: some View {
        switch step {
        case .owner:
            NovaButton(label: RDLocalization.string("localizable.nova.intake.continue", table: .localizable, fallback: "Devam et"),
                symbol: "chevron.right") { step = .sector }
                .accessibilityIdentifier("analysis.intake.continue.owner")
        case .sector:
            NovaButton(label: RDLocalization.string("localizable.nova.intake.continue", table: .localizable, fallback: "Devam et"),
                symbol: "chevron.right", isEnabled: draft.sectorID != nil) { step = .focus }
                .accessibilityIdentifier("analysis.intake.continue.sector")
        case .focus:
            VStack(alignment: .leading, spacing: 7) {
                NovaButton(label: RDLocalization.string("localizable.nova.intake.start", table: .localizable, fallback: "Analizi başlat"),
                    symbol: "sparkles", isEnabled: draft.isReady, isLoading: isStarting) { onStart() }
                    .accessibilityIdentifier("analysis.intake.start")
                if !draft.isReady {
                    NovaText(text: RDLocalization.string("localizable.nova.intake.focus.required", table: .localizable,
                        fallback: "Başlatmak için en az bir odak seçin."), style: .metaQuiet)
                }
            }
        }
    }

    private func back() {
        switch step {
        case .owner: break
        case .sector: step = .owner
        case .focus: step = .sector
        }
    }
}
