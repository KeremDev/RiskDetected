import SwiftUI

struct AnalysisSectorPickerView: View {
    let items: [AnalysisSectorPickerItem]
    @Binding var selected: AnalysisSectorID?
    var onContinue: () -> Void

    private let chipColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            sectorGridSection
                .padding(.bottom, 4)

            RDButton(title: "Devam et", style: .primary, a11yID: "analysis_sector_continue_button") {
                onContinue()
            }
            .disabled(selected == nil)
            .opacity(selected == nil ? 0.45 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 8)
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
        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 6) {
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
                        .font(.system(size: RDFontScale.size(12), weight: .semibold))
                    if let badge = primaryBadge(for: item.badges) {
                        Text(badge.compactLabel)
                            .font(.system(size: RDFontScale.size(8), weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.rdFog)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                Text(item.sector.label())
                    .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
            onContinue: {}
        )
    }
}
