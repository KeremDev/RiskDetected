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

/// Photo → company → sector → focus, in that order. Every step can be revisited
/// with the back control; nothing is decided for the expert without being shown.
struct NovaAnalysisIntakeScreen: View {
    let companies: [NovaAnalysisCompanyOption]
    let sectors: [NovaAnalysisSectorOption]
    let focuses: [NovaAnalysisFocusOption]
    @Binding var draft: NovaAnalysisIntakeDraft
    var isStarting = false
    let onCancel: () -> Void
    let onStart: () -> Void
    @State private var step: NovaAnalysisIntakeStep = .owner
    @Environment(\.colorScheme) private var scheme

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

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    NovaHelpHint(text: stepHint)
                    switch step {
                    case .owner: ownerStep
                    case .sector: sectorStep
                    case .focus: focusStep
                    }
                    footer
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NovaBackButton(isEnabled: !isStarting) { back() }
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: RDLocalization.string("localizable.nova.intake.title", table: .localizable, fallback: "Fotoğraf Analizi"), style: .screenTitle)
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.intake.photo.count", table: .localizable,
                        fallback: "%d fotoğraf · %@"), draft.photoCount, stepTitle), style: .metaQuiet)
                }
                Spacer(minLength: 0)
            }
            steps
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
        VStack(alignment: .leading, spacing: 10) {
            ownerRow(title: RDLocalization.string("localizable.nova.intake.owner.none", table: .localizable, fallback: "Firmasız devam et"),
                     detail: RDLocalization.string("localizable.nova.intake.owner.none.detail", table: .localizable,
                        fallback: "Analiz hesabınızda kalır; sonradan bir firmaya atayabilirsiniz."),
                     symbol: "person", isSelected: draft.owner == .unassigned,
                     identifier: "analysis.intake.owner.none") {
                draft.choose(owner: .unassigned, catalog: catalog)
            }
            if companies.isEmpty {
                NovaCard(padding: 16) {
                    NovaText(text: RDLocalization.string("localizable.nova.intake.owner.empty", table: .localizable,
                        fallback: "Bu hesapta pilot firma yok. Firmasız devam edebilirsiniz."), style: .metaQuiet)
                }
            }
            ForEach(companies) { company in
                ownerRow(title: company.name, detail: companyDetail(company), symbol: "building.2",
                         isSelected: draft.owner.companyID == company.id,
                         identifier: "analysis.intake.owner.\(company.id.uuidString.lowercased())") {
                    draft.choose(owner: .company(id: company.id, name: company.name, sector: company.sector),
                                 catalog: catalog)
                }
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
            NovaCard(padding: 14, border: isSelected ? NovaColorToken.accentInk.color(in: scheme) : .clear) {
                HStack(spacing: 10) {
                    NovaIcon(symbol: symbol, size: 18)
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
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var catalog: [NovaSectorCandidate] {
        sectors.map { .init(id: $0.id, labels: [$0.label]) }
    }

    // MARK: sector

    @ViewBuilder private var sectorStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The note only stands while the pre-selection is still untouched.
            if draft.sectorCameFromCompany, let name = draft.owner.companyName {
                NovaCard(padding: 12, tint: NovaColorToken.statusInfoBg.color(in: scheme)) {
                    HStack(alignment: .top, spacing: 8) {
                        NovaIcon(symbol: "sparkle", size: 15)
                            .foregroundStyle(NovaColorToken.statusInfoInk.color(in: scheme))
                        NovaText(text: String(format: RDLocalization.string("localizable.nova.intake.sector.auto", table: .localizable,
                            fallback: "%@ firmasının sektörü otomatik seçildi. İsterseniz değiştirebilirsiniz."), name),
                            style: .metaQuiet, color: NovaColorToken.statusInfoInk.color(in: scheme))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("analysis.intake.sector.auto")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(sectors) { sector in
                    sectorChip(sector)
                }
            }
        }
    }

    private func sectorChip(_ sector: NovaAnalysisSectorOption) -> some View {
        let isSelected = draft.sectorID == sector.id
        return Button { draft.choose(sector: sector.id) } label: {
            NovaCard(padding: 12, border: isSelected ? NovaColorToken.accentInk.color(in: scheme) : .clear,
                     tint: isSelected ? NovaColorToken.statusSuccessBg.color(in: scheme) : nil) {
                VStack(alignment: .leading, spacing: 4) {
                    NovaIcon(symbol: sector.symbol, size: 17)
                        .foregroundStyle(isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                                    : NovaColorToken.textSecondary.color(in: scheme))
                    NovaText(text: sector.label, style: .cardTitle)
                }.frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("analysis.intake.sector.\(sector.id)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: focus

    @ViewBuilder private var focusStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(focuses) { focus in
                focusRow(focus)
            }
        }
    }

    private func focusRow(_ focus: NovaAnalysisFocusOption) -> some View {
        let isSelected = draft.focusIDs.contains(focus.id)
        return Button {
            guard !focus.isLocked else { return }
            draft.toggle(focus: focus.id)
        } label: {
            NovaCard(padding: 12, border: isSelected ? NovaColorToken.accentInk.color(in: scheme) : .clear) {
                HStack(alignment: .top, spacing: 10) {
                    NovaIcon(symbol: focus.symbol, size: 18)
                        .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            NovaText(text: focus.title, style: .cardTitle)
                            if focus.isLocked { NovaStatusPill(label: focus.lockLabel, status: .neutral, showsDot: false) }
                        }
                        NovaText(text: focus.detail, style: .metaQuiet)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(focus.isLocked ? NovaColorToken.borderStrong.color(in: scheme)
                            : isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                         : NovaColorToken.borderStrong.color(in: scheme))
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.opacity(focus.isLocked ? 0.55 : 1)
        }.buttonStyle(.plain).disabled(focus.isLocked)
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
            VStack(alignment: .leading, spacing: 8) {
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
        case .owner: onCancel()
        case .sector: step = .owner
        case .focus: step = .sector
        }
    }
}
