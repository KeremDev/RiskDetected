import SwiftUI

struct AnalysisSectorPickerView: View {
    let items: [AnalysisSectorPickerItem]
    @Binding var selected: AnalysisSectorID?
    var onContinue: () -> Void
    var onShowAll: () -> Void

    private var inlineItems: [AnalysisSectorPickerItem] {
        AnalysisSectorPreferences.inlineVisibleItems(from: items).0
    }

    private var hasMoreItems: Bool {
        AnalysisSectorPreferences.inlineVisibleItems(from: items).1
    }

    private let chipColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    chipGrid
                    if hasMoreItems {
                        Button(action: onShowAll) {
                            HStack(spacing: 6) {
                                Text("Tüm sektörleri göster")
                                    .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: RDFontScale.size(12), weight: .bold))
                            }
                            .foregroundStyle(Color.rdSelected)
                        }
                        .buttonStyle(RDPressableButtonStyle())
                        .accessibilityIdentifier("analysis_sector_more_button")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            RDButton(title: "Devam et", style: .primary, a11yID: "analysis_sector_continue_button") {
                onContinue()
            }
            .disabled(selected == nil)
            .opacity(selected == nil ? 0.45 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.rdPaper.ignoresSafeArea())
        .accessibilityIdentifier("analysis_sector_picker")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analiz kapsamını seç")
                .font(.system(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(Color.rdBlack)
            Text("Bu fotoğrafı hangi sektörün saha koşullarına göre değerlendirelim?\nRisk öncelikleri ve öneriler seçtiğin sektöre göre uyarlanır.")
                .font(.system(size: RDFontScale.size(14), design: .rounded))
                .foregroundStyle(Color.rdSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analysis_sector_picker_title")
    }

    private var chipGrid: some View {
        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
            ForEach(inlineItems) { item in
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: item.sector.icon)
                        .font(.system(size: RDFontScale.size(12), weight: .semibold))
                    if let badge = primaryBadge(for: item.badges) {
                        Text(badge.label)
                            .font(.system(size: RDFontScale.size(9), weight: .heavy, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.rdFog)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                Text(item.sector.label())
                    .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .foregroundStyle(isSelected ? Color.white : Color.rdBlack)
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
                                .font(.system(size: RDFontScale.size(15), weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(item.sector.subtitle)
                                .font(.system(size: RDFontScale.size(12), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                        }
                        Spacer(minLength: 0)
                        if let badge = item.badges.contains(.recommended) ? AnalysisSectorBadge.recommended :
                            item.badges.contains(.lastUsed) ? AnalysisSectorBadge.lastUsed : nil {
                            Text(badge.label)
                                .font(.system(size: RDFontScale.size(10), weight: .bold, design: .rounded))
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
            .searchable(text: $searchText, prompt: "Sektör ara")
            .accessibilityIdentifier("analysis_sector_search_field")
            .navigationTitle("Tüm sektörler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
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
            onContinue: {},
            onShowAll: {}
        )
    }
}
