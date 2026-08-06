import SwiftUI

struct FilterSheet: View {
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var dateFilter: String = RDLocalization.string("localizable.filter.sheet.bu.hafta.bd342175", table: .localizable, fallback: "Bu hafta")
    @State private var selectedLevels: Set<RiskLevel> = [.critical, .high]
    @State private var selectedKinds: Set<String> = []

    private let dateOptions = [RDLocalization.string("localizable.filter.sheet.bugun.5e78d032", table: .localizable, fallback: "Bugün"), RDLocalization.string("localizable.filter.sheet.bu.hafta.6ef21499", table: .localizable, fallback: "Bu hafta"), RDLocalization.string("localizable.filter.sheet.bu.ay.3e4f935f", table: .localizable, fallback: "Bu ay"), RDLocalization.string("localizable.filter.sheet.son.90.gun.d5e15064", table: .localizable, fallback: "Son 90 gün"), RDLocalization.string("localizable.filter.sheet.tumu.de3dc3ab", table: .localizable, fallback: "Tümü")]
    private let kindOptions = [RDLocalization.string("localizable.filter.sheet.genel.ca283d14", table: .localizable, fallback: "Genel"), "KKD", RDLocalization.string("localizable.filter.sheet.isaretleme.81bc8740", table: .localizable, fallback: "İşaretleme"), RDLocalization.string("localizable.filter.sheet.sektor.0d1f5675", table: .localizable, fallback: "Sektör"), RDLocalization.string("localizable.filter.sheet.acil.eb5edb91", table: .localizable, fallback: "Acil"), RDLocalization.string("localizable.filter.sheet.prosedur.3d2127b9", table: .localizable, fallback: "Prosedür")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdGreen)
                        .frame(width: 42, height: 42)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(RDLocalization.string("localizable.filter.sheet.analizleri.filtrele.a9296aa3", table: .localizable, fallback: "Analizleri filtrele"))
                            .font(.system(size: RDFontScale.size(20), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                        Text(RDLocalization.string("localizable.filter.sheet.tarih.risk.seviyesi.ve.odak.alanina.gore.daralt.8b8a317e", table: .localizable, fallback: "Tarih, risk seviyesi ve odak alanına göre daralt."))
                            .font(.system(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .frame(width: 38, height: 38)
                            .background(Color.rdWhite)
                            .clipShape(Circle())
                            .shadow(color: Color.rdOnyx.opacity(0.10), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(RDPressableButtonStyle())
                    .accessibilityLabel(RDLocalization.string("localizable.filter.sheet.filtre.penceresini.kapat.23394e9a", table: .localizable, fallback: "Filtre penceresini kapat"))
                }
                .padding(.top, 6)

                section("Tarih") {
                    chipRow(options: dateOptions, isSelected: { $0 == dateFilter }) {
                        dateFilter = $0
                    }
                }

                section(RDLocalization.string("localizable.filter.sheet.risk.seviyesi.be00fbef", table: .localizable, fallback: "Risk seviyesi")) {
                    HStack(spacing: 6) {
                        ForEach([RiskLevel.critical, .high, .medium, .low], id: \.self) { lvl in
                            riskChip(level: lvl)
                        }
                    }
                }

                section(RDLocalization.string("localizable.filter.sheet.analiz.turu.ebbe9acb", table: .localizable, fallback: "Analiz türü")) {
                    chipRow(options: kindOptions, isSelected: { selectedKinds.contains($0) }) { kind in
                        if selectedKinds.contains(kind) { selectedKinds.remove(kind) }
                        else { selectedKinds.insert(kind) }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        dateFilter = RDLocalization.string("localizable.filter.sheet.tumu.8f51a7df", table: .localizable, fallback: "Tümü")
                        selectedLevels = []
                        selectedKinds = []
                    } label: {
                        Text(RDLocalization.string("localizable.filter.sheet.sifirla.77de5bea", table: .localizable, fallback: "Sıfırla"))
                            .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .frame(width: 92, height: 48)
                            .background(Color.rdFog)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.rdLine, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(RDPressableButtonStyle())

                    RDButton(title: RDLocalization.string("localizable.filter.sheet.12.sonucu.goster.d4e56bf2", table: .localizable, fallback: "12 sonucu göster"), style: .primary) {
                        onConfirm()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
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
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
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
                        .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .foregroundStyle(active ? .white : Color.rdCharcoal)
                        .background(
                            Capsule()
                                .fill(active ? Color.rdSelected : Color.rdWhite)
                                .overlay(
                                    Capsule().stroke(active ? Color.clear : Color.rdLine, lineWidth: 1)
                                )
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
                    .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(active ? .white : Color.rdCharcoal)
            .background(
                Capsule()
                    .fill(active ? Color.rdSelected : Color.rdWhite)
                    .overlay(Capsule().stroke(active ? Color.clear : Color.rdLine, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FilterSheet(onConfirm: {})
}
