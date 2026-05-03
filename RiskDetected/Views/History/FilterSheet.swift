import SwiftUI

struct FilterSheet: View {
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var dateFilter: String = "Bu hafta"
    @State private var selectedLevels: Set<RiskLevel> = [.critical, .high]
    @State private var selectedKinds: Set<String> = []

    private let dateOptions = ["Bugün", "Bu hafta", "Bu ay", "Son 90 gün", "Tümü"]
    private let kindOptions = ["Genel", "KKD", "İşaretleme", "Sektör", "Acil", "Prosedür"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Filtrele")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 6)

                section("Tarih") {
                    chipRow(options: dateOptions, isSelected: { $0 == dateFilter }) {
                        dateFilter = $0
                    }
                }

                section("Risk seviyesi") {
                    HStack(spacing: 6) {
                        ForEach([RiskLevel.critical, .high, .medium, .low], id: \.self) { lvl in
                            riskChip(level: lvl)
                        }
                    }
                }

                section("Analiz türü") {
                    chipRow(options: kindOptions, isSelected: { selectedKinds.contains($0) }) { kind in
                        if selectedKinds.contains(kind) { selectedKinds.remove(kind) }
                        else { selectedKinds.insert(kind) }
                    }
                }

                HStack(spacing: 8) {
                    RDButton(title: "Sıfırla", style: .secondary) {
                        dateFilter = "Tümü"
                        selectedLevels = []
                        selectedKinds = []
                    }
                    .frame(maxWidth: .infinity)

                    RDButton(title: "12 sonucu göster", style: .primary) {
                        onConfirm()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(2)
                }
                .padding(.top, 6)

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .background(Color.rdPaper)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.rdSlate)
            content()
        }
    }

    private func chipRow(options: [String],
                         isSelected: @escaping (String) -> Bool,
                         onTap: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(options, id: \.self) { opt in
                let active = isSelected(opt)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onTap(opt)
                } label: {
                    Text(opt)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .foregroundStyle(active ? .white : Color.rdCharcoal)
                        .background(
                            Capsule().fill(active ? Color.rdBlack : Color.rdFog)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func riskChip(level: RiskLevel) -> some View {
        let active = selectedLevels.contains(level)
        return Button {
            if active { selectedLevels.remove(level) } else { selectedLevels.insert(level) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(level.color).frame(width: 8, height: 8)
                Text(level.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(active ? .white : Color.rdCharcoal)
            .background(Capsule().fill(active ? Color.rdBlack : Color.rdFog))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FilterSheet(onConfirm: {})
}
