import SwiftUI

struct AnalysisSectorPickerView: View {
    let items: [AnalysisSectorPickerItem]
    @Binding var selected: AnalysisSectorID?
    var onContinue: () -> Void

    private let chipColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let chipHeight: CGFloat = 74
    private let chipIconSize: CGFloat = 14
    private let chipTitleSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            sectorGridSection
                .padding(.bottom, 10)

            Spacer(minLength: 10)

            continueButton
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.rdPaper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis_sector_picker")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RDLocalization.string("analysis.analysis.sector.picker.view.analiz.kapsamini.sec.7753a6c8", table: .analysis, fallback: "Analiz kapsamını seç"))
                .font(RDTypography.font(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(Color.rdBlack)
            Text(RDLocalization.string("analysis.analysis.sector.picker.view.bu.fotografi.hangi.sektorun.saha.kosullarina.gor.c6c832db", table: .analysis, fallback: "Bu fotoğrafı hangi sektörün saha koşullarına göre değerlendirelim? Risk öncelikleri ve öneriler seçtiğin sektöre göre uyarlanır."))
                .font(RDTypography.font(size: RDFontScale.size(14), design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analysis_sector_picker_title")
    }

    private var continueButton: some View {
        RDButton(
            title: RDLocalization.string("analysis.analysis.sector.picker.view.devam.et.04ec7e11", table: .analysis, fallback: "Devam et"),
            style: .primary,
            backgroundOverride: .rdCTA,
            a11yID: "analysis_sector_continue_button"
        ) {
            onContinue()
        }
        .disabled(selected == nil)
        .opacity(selected == nil ? 0.45 : 1)
        .padding(.horizontal, 20)
    }

    private var sectorGridSection: some View {
        ViewThatFits(in: .vertical) {
            chipGrid
            ScrollView {
                chipGrid
            }
            .modifier(ShrinkScrollToContentIfAvailable())
        }
        .padding(.horizontal, 20)
    }

    private var chipGrid: some View {
        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                sectorChip(item)
            }
        }
    }

    private func sectorChip(_ item: AnalysisSectorPickerItem) -> some View {
        let isSelected = selected == item.sector
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selected = item.sector
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: item.sector.icon)
                        .font(RDTypography.font(size: RDFontScale.size(chipIconSize), weight: .semibold))
                        .foregroundStyle(iconColor(for: item.sector))
                    if let badge = primaryBadge(for: item.badges) {
                        Text(badge.compactLabel)
                            .font(RDTypography.font(size: RDFontScale.size(8), weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isSelected ? Color.rdBlack : Color.rdSlate)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.white.opacity(0.86) : Color.rdFog)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                Text(item.sector.label())
                    .font(RDTypography.font(size: RDFontScale.size(chipTitleSize), weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.rdBlack)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: chipHeight, maxHeight: chipHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.rdSelected : Color.rdWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.rdSelected : Color.rdLine, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityIdentifier(item.sector.accessibilityChipID)
        .accessibilityLabel(item.sector.label())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func primaryBadge(for badges: Set<AnalysisSectorBadge>) -> AnalysisSectorBadge? {
        if badges.contains(.recommended) { return .recommended }
        if badges.contains(.lastUsed) { return .lastUsed }
        return nil
    }

    private func iconColor(for sector: AnalysisSectorID) -> Color {
        switch sector {
        case .construction: return Color.rdHigh
        case .manufacturing: return Color.rdInfo
        case .mining: return Color.rdSlate
        case .energy: return Color.rdMedium
        case .office: return Color(hex: "#5B6CFF")
        case .logisticsWarehouse: return Color(hex: "#2563EB")
        case .chemicalLaboratory: return Color(hex: "#7C3AED")
        case .healthcare: return Color.rdCritical
        case .foodProduction: return Color(hex: "#0F766E")
        case .agricultureLivestock: return Color.rdLow
        case .retail: return Color(hex: "#DB2777")
        case .municipalFieldServices: return Color(hex: "#C2410C")
        case .education: return Color(hex: "#4F46E5")
        case .hospitality: return Color(hex: "#9333EA")
        case .general: return Color.rdCharcoal
        }
    }
}

private struct ShrinkScrollToContentIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.scrollBounceBehavior(.basedOnSize, axes: .vertical)
        } else {
            content
        }
    }
}

struct AnalysisSectorPickerSheet: View {
    let items: [AnalysisSectorPickerItem]
    @Binding var selected: AnalysisSectorID?
    @Binding var searchText: String
    var onSelect: (AnalysisSectorID) -> Void

    @Environment(\.dismiss) private var dismiss

    private var filteredItems: [AnalysisSectorPickerItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            let haystack = [
                item.sector.label(),
                item.sector.subtitle,
                item.sector.rawValue,
            ].joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return haystack.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredItems) { item in
                Button {
                    selected = item.sector
                    onSelect(item.sector)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.sector.icon)
                            .foregroundStyle(Color.rdSelected)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.sector.label())
                                .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(item.sector.subtitle)
                                .font(RDTypography.font(size: RDFontScale.size(12), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                        }
                        Spacer(minLength: 0)
                        if let badge = item.badges.contains(.recommended) ? AnalysisSectorBadge.recommended :
                            item.badges.contains(.lastUsed) ? AnalysisSectorBadge.lastUsed : nil {
                            Text(badge.label)
                                .font(RDTypography.font(size: RDFontScale.size(10), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                        }
                        if selected == item.sector {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.rdSelected)
                        }
                    }
                }
                .accessibilityIdentifier(item.sector.accessibilityChipID)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: RDLocalization.string("analysis.analysis.sector.picker.view.sektor.ara.d2562471", table: .analysis, fallback: "Sektör ara"))
            .accessibilityIdentifier("analysis_sector_search_field")
            .navigationTitle(RDLocalization.string("analysis.analysis.sector.picker.view.tum.sektorler.9c18e12c", table: .analysis, fallback: "Tüm sektörler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(RDLocalization.string("analysis.analysis.sector.picker.view.kapat.c36ab4f2", table: .analysis, fallback: "Kapat")) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("analysis_sector_sheet")
    }
}

#Preview("Aktif Sektör Seçimi") {
    StatefulSectorPickerPreview()
}

private struct StatefulSectorPickerPreview: View {
    @State private var selected: AnalysisSectorID? = .construction

    private var items: [AnalysisSectorPickerItem] {
        AnalysisSectorPreferences.pickerItems(
            onboardingSectors: [.construction, .manufacturing, .mining],
            lastUsed: .logisticsWarehouse
        )
    }

    var body: some View {
        AnalysisSectorPickerView(
            items: items,
            selected: $selected,
            onContinue: {}
        )
    }
}
